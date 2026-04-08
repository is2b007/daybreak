# Spec 09 — HEY Email triage

Add read-only HEY Email support: pull Imbox, Reply Later, and Set Aside into Daybreak, and give the user a quiet morning-ritual surface for turning a few emails into "sometime this week" tasks and dismissing the rest. Daybreak never writes to HEY — every write-back action (archive, mark read, move folders, reply) happens in HEY itself.

## Context

Daybreak's HEY integration (spec 03) is OAuth + calendar + todos + journal + time tracking. Email was deliberately skipped then: writing a second email client violates "three views only" and pulls the user away from planning. This spec adds triage — the *minimum* amount of email the planner needs so that "the important thing in my inbox" can become "the thing on my week" without leaving Daybreak.

Triage is a ritual artifact, not a destination. Every morning, emails are cached at 6am. Morning ritual step 2 shows a quiet footnote (`"N emails waiting in HEY. Triage them."`) only when something is waiting. The user opens `/triage`, stamps the few that matter into the week's Sometime column, dismisses the rest, and leaves. On-demand sync fires when `/triage` opens so the view always reflects recent state, but there's no polling and no notifications.

The cache table (`hey_emails`) is separate from `task_assignments`. When the user triages an email, a **plain local `TaskAssignment`** is created (`source: :local`, `week_bucket: "sometime"`) — the user's commitment is "I'll do this thing," not "I'll handle this email." Once triaged, the task is indistinguishable from any other local task. This keeps us out of the trap of overloading the task model with an email state machine.

## Files that need work

| File | What's missing |
|---|---|
| `db/migrate/YYYYMMDDHHMMSS_create_hey_emails.rb` | New migration — cache table with folder enum + local soft-delete stamps. |
| `app/models/hey_email.rb` | New model — folder enum, `for_triage` scope, `dismiss!` / `triage!`. |
| `app/models/user.rb` | `has_many :hey_emails, dependent: :destroy`. |
| `app/services/hey_client.rb` | Three new read-only methods: `imbox`, `reply_later`, `set_aside`. Private `fetch_box` to unwrap the `BoxShowResponse` shape. |
| `app/jobs/sync_hey_emails_job.rb` | New job — upsert + prune, 25-row cap per folder, preserves local state stamps. |
| `config/routes.rb` | `resource :triage, only: [:show]` + `resources :hey_emails, only: [] do member { patch :triage; patch :dismiss } end`. |
| `app/controllers/triage_controller.rb` | New — redirect if not connected, fire on-demand sync, group emails by folder. |
| `app/controllers/hey_emails_controller.rb` | New — `#triage` creates a local task; `#dismiss` stamps `dismissed_at`; both respond Turbo Stream. |
| `app/views/triage/show.html.erb` + `_hey_email.html.erb` | New views — three sections, row partial with "This week" + "Dismiss" forms. |
| `app/views/rituals/_morning_step_2.html.erb` | Append a gated footnote linking to `triage_path`. |
| `app/views/settings/show.html.erb` | "Triage inbox" sub-action under the HEY row when connected. |
| `app/views/onboarding/_step_3_hey.html.erb` | Fifth `hey-feature` row mentioning email triage. |
| `app/controllers/hey_connections_controller.rb` | `destroy` clears `hey_emails` cache before wiping tokens. |
| `app/assets/stylesheets/application.css` | BEM classes for `.triage*`, `.triage-row*`, `.ritual__footnote`, `.settings__sub-action`. |
| `config/recurring.yml` | `sync_hey_emails` daily at 6am (NOT every 15 min — email triage is a morning activity). |
| `config/environments/test.rb` | Active Record encryption keys for the test environment so fixtures can populate `hey_access_token`. |

## Preflight — verify HEY Email API access

HEY Email is a separate 37signals product from HEY Calendar. Before writing code, confirm that the existing Launchpad OAuth token works against HEY Email endpoints. The public reference is `github.com/basecamp/hey-cli` (README + `API-COVERAGE.md`) and `github.com/basecamp/hey-sdk` (`openapi.json`).

Canonical paths (confirmed from `hey-sdk`):

```
GET /imbox.json      → BoxShowResponse { id, kind, name, postings: [Posting, ...] }
GET /laterbox.json   → BoxShowResponse
GET /asidebox.json   → BoxShowResponse
```

A `Posting` is polymorphic by `kind`: `"topic"` and `"bundle"` are triagable (a conversation or a grouped set), `"entry"` is an individual reply inside a topic and should be skipped. Key posting fields used: `id`, `kind`, `name` (subject), `summary` (snippet), `app_url` (deep link back into HEY), `observed_at` (received time), `creator.name` / `creator.email_address`.

If the canonical paths return 401/403 on a live account because the Launchpad app registration doesn't include HEY Email scope, re-register the app at `launchpad.37signals.com` with HEY Email ticked. Do not proceed until a real account can `GET /imbox.json` and receive a `BoxShowResponse`.

## Implementation

### 1. Migration

```ruby
# db/migrate/YYYYMMDDHHMMSS_create_hey_emails.rb
class CreateHeyEmails < ActiveRecord::Migration[8.1]
  def change
    create_table :hey_emails do |t|
      t.references :user, null: false, foreign_key: true
      t.string :external_id, null: false
      t.integer :folder, null: false        # enum: imbox(0), reply_later(1), set_aside(2)
      t.string :sender_name
      t.string :sender_email
      t.string :subject, null: false
      t.text :snippet
      t.datetime :received_at, null: false
      t.string :hey_url                     # deep link back into HEY
      t.datetime :dismissed_at              # local-only soft delete
      t.datetime :triaged_at                # local-only, set when user sends to Sometime
      t.timestamps
    end

    add_index :hey_emails, [ :user_id, :folder ]
    add_index :hey_emails, [ :user_id, :external_id ], unique: true
    add_index :hey_emails, [ :user_id, :received_at ]
  end
end
```

No change to `task_assignments`. No `hey_email_id` column. No new source enum value. The task created by triage is a plain local task.

### 2. HeyEmail model

```ruby
# app/models/hey_email.rb
class HeyEmail < ApplicationRecord
  belongs_to :user

  enum :folder, { imbox: 0, reply_later: 1, set_aside: 2 }

  validates :external_id, :subject, :received_at, presence: true

  scope :active, -> { where(dismissed_at: nil, triaged_at: nil) }
  scope :ordered, -> { order(received_at: :desc) }
  scope :for_triage, -> { active.ordered }

  def dismiss!
    update!(dismissed_at: Time.current)
  end

  def triage!
    update!(triaged_at: Time.current)
  end

  def handled?
    dismissed_at.present? || triaged_at.present?
  end
end
```

Add to `app/models/user.rb` alongside the other HEY associations:

```ruby
has_many :hey_emails, dependent: :destroy
```

### 3. HeyClient — read-only email methods

```ruby
# app/services/hey_client.rb  (additions only)

def imbox
  fetch_box("/imbox.json")
end

def reply_later
  fetch_box("/laterbox.json")
end

def set_aside
  fetch_box("/asidebox.json")
end

private

def fetch_box(path)
  data = get(path)
  return [] unless data.is_a?(Hash)
  postings = data["postings"]
  postings.is_a?(Array) ? postings : []
end
```

Reuses the existing private `get` / `request` helpers (which already handle auth headers and the 401 refresh-and-retry from spec 03). **No `post`, `patch`, or `delete` methods for email.** Daybreak is a read-only HEY Email consumer by design.

### 4. SyncHeyEmailsJob — upsert + prune

```ruby
# app/jobs/sync_hey_emails_job.rb
class SyncHeyEmailsJob < ApplicationJob
  queue_as :sync

  PER_FOLDER_CAP = 25

  FOLDER_FETCHERS = {
    imbox: :imbox,
    reply_later: :reply_later,
    set_aside: :set_aside
  }.freeze

  def perform(user_id)
    user = User.find(user_id)
    return unless user.hey_connected?

    client = HeyClient.new(user)

    FOLDER_FETCHERS.each do |folder, method|
      postings = client.public_send(method)
      next unless postings.is_a?(Array)

      postings = postings.select { |p| triagable?(p) }.first(PER_FOLDER_CAP)
      upsert(user, folder, postings)
      prune_stale(user, folder, postings)
    end
  rescue HeyClient::AuthError => e
    Rails.logger.warn("HEY email sync failed for user #{user_id}: #{e.message}")
  end

  private

  def triagable?(posting)
    %w[topic bundle].include?(posting["kind"])
  end

  def upsert(user, folder, postings)
    postings.each do |posting|
      row = user.hey_emails.find_or_initialize_by(external_id: posting["id"].to_s)
      row.assign_attributes(
        folder: folder,
        sender_name: posting.dig("creator", "name"),
        sender_email: posting.dig("creator", "email_address"),
        subject: posting["name"].presence || "(no subject)",
        snippet: posting["summary"],
        received_at: parse_time(posting["observed_at"] || posting["updated_at"] || posting["created_at"]),
        hey_url: posting["app_url"]
      )
      row.save! if row.changed?
    end
  end

  def prune_stale(user, folder, postings)
    current_ids = postings.map { |p| p["id"].to_s }
    scope = user.hey_emails.where(folder: folder, dismissed_at: nil, triaged_at: nil)
    scope = scope.where.not(external_id: current_ids) if current_ids.any?
    scope.delete_all
  end

  def parse_time(value)
    return Time.current if value.blank?
    Time.parse(value.to_s)
  rescue ArgumentError
    Time.current
  end
end
```

Three critical properties of this job:

1. **`assign_attributes` never touches `dismissed_at` / `triaged_at`.** Local state is sticky — once the user has acted on a row, sync refreshes only display fields (subject, snippet, folder, received_at, hey_url).
2. **Prune scope filters by `dismissed_at: nil, triaged_at: nil`.** Rows that the user has already handled are preserved even if they disappear from HEY. This keeps the triage list consistent and avoids re-offering something the user already dismissed.
3. **25-row cap per folder.** Older stuff stays in HEY where it belongs — triage is for recent arrivals, not archive archaeology.

### 5. Routes

```ruby
# config/routes.rb  (after the HEY OAuth routes)
resource :triage, only: [ :show ], controller: "triage"
resources :hey_emails, only: [] do
  member do
    patch :triage
    patch :dismiss
  end
end
```

### 6. TriageController

```ruby
# app/controllers/triage_controller.rb
class TriageController < ApplicationController
  def show
    unless current_user.hey_connected?
      redirect_to root_path, alert: "Connect HEY first from Settings." and return
    end

    # Fire-and-forget on-demand refresh so the view always reflects recent state.
    SyncHeyEmailsJob.perform_later(current_user.id)

    @emails_by_folder = current_user.hey_emails
      .for_triage
      .group_by(&:folder)
  end
end
```

### 7. HeyEmailsController

```ruby
# app/controllers/hey_emails_controller.rb
class HeyEmailsController < ApplicationController
  before_action :set_email

  def triage
    week_start = Date.current.beginning_of_week(:monday)

    current_user.task_assignments.create!(
      source: :local,
      title: @email.subject,
      week_start_date: week_start,
      week_bucket: "sometime",
      size: :medium,
      status: :pending
    )
    @email.triage!

    respond_removed("Added to this week.")
  end

  def dismiss
    @email.dismiss!
    respond_removed("Dismissed.")
  end

  private

  def set_email
    @email = current_user.hey_emails.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    # Handles the sync race: user clicks an action mid-sync that just deleted the row.
    respond_to do |format|
      format.turbo_stream { head :no_content }
      format.html { redirect_to triage_path, notice: "Already handled." }
    end
  end

  def respond_removed(notice)
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.remove("hey_email_#{@email.id}") }
      format.html { redirect_to triage_path, notice: notice }
    end
  end
end
```

Two things worth calling out:

- Looking the row up via `current_user.hey_emails.find(params[:id])` scopes the action to the current user. Attempting to triage another user's email is a no-op (`head :no_content`) — same behavior as the sync-race case.
- `turbo_stream.remove("hey_email_#{@email.id}")` targets the partial's root `id`; the section header stays put even when the last row in a section is removed, because the header is rendered in the parent view, not inside the partial.

### 8. Views

`app/views/triage/show.html.erb` renders three sections in a fixed order (Imbox / Reply Later / Set Aside). Each section is only rendered when it has rows — empty sections disappear entirely, keeping the page quiet when the inbox is nearly handled.

`app/views/triage/_hey_email.html.erb` renders a row with sender, linked subject (opens `email.hey_url` in a new tab so the user can read the full thread in HEY), snippet, relative time, and two `button_to` forms:

```erb
<%= button_to "This week", triage_hey_email_path(email), method: :patch, form: { data: { turbo_stream: true } }, class: "triage-row__action triage-row__action--primary" %>
<%= button_to "Dismiss", dismiss_hey_email_path(email), method: :patch, form: { data: { turbo_stream: true } }, class: "triage-row__action" %>
```

The partial's root element is `<article id="hey_email_<%= email.id %>" class="triage-row">` so the Turbo Stream `remove` target matches.

Morning ritual step 2 — `app/views/rituals/_morning_step_2.html.erb` — appends a footnote before the Continue button:

```erb
<% if current_user.hey_connected? %>
  <% triage_count = current_user.hey_emails.for_triage.count %>
  <% if triage_count > 0 %>
    <p class="ritual__footnote">
      <%= pluralize(triage_count, "email") %> waiting in HEY.
      <%= link_to "Triage them", triage_path %>.
    </p>
  <% end %>
<% end %>
```

Do NOT render emails inline in step 2 — the ritual stays calm, and triage is reached by choice.

### 9. Disconnect clears the cache

```ruby
# app/controllers/hey_connections_controller.rb
def destroy
  current_user.hey_emails.delete_all
  current_user.update!(hey_access_token: nil, hey_refresh_token: nil, hey_token_expires_at: nil)
  redirect_to settings_path, notice: "HEY is disconnected."
end
```

Not via `dependent: :destroy` — the user isn't destroyed, just the connection. The explicit `delete_all` is a single fast statement (no callbacks needed; `HeyEmail` has no dependents).

### 10. Recurring sync

```yaml
# config/recurring.yml
sync_hey_emails:
  command: "User.where.not(hey_access_token: nil).find_each { |u| SyncHeyEmailsJob.perform_later(u.id) }"
  queue: sync
  schedule: at 6am every day
```

Not every 15 minutes. Email triage is a morning activity — ambient awareness of new email is exactly the anxiety Daybreak is trying not to create.

### 11. Test environment encryption keys

The existing `User` model encrypts `hey_access_token` / `hey_refresh_token` (spec 03), but no existing test populated those columns. The new job and controller tests do, which requires encryption credentials for the `test` environment:

```ruby
# config/environments/test.rb  (inside the configure block)
config.active_record.encryption.primary_key = "test_primary_key_0000000000000000"
config.active_record.encryption.deterministic_key = "test_deterministic_key_000000000"
config.active_record.encryption.key_derivation_salt = "test_key_derivation_salt_0000000"
```

These are throwaway keys scoped to the test environment — real keys still live in `config/credentials.yml.enc`.

## Testing

Three Minitest files (matching existing project style — no mocking library, and **Minitest 6 dropped `Object#stub`**, so class-method stubs use `define_singleton_method`):

- **`test/models/hey_email_test.rb`** — `for_triage` scope filters dismissed + triaged and orders newest first; `dismiss!` and `triage!` stamp columns; validations require subject and received_at.
- **`test/jobs/sync_hey_emails_job_test.rb`** — stubs `HeyClient.new` via a `with_hey_client(stub)` helper that saves/restores the original method. Covers: first-run create, idempotency (no updated_at churn on unchanged rows), prune preserves triaged + dismissed rows, upsert doesn't clear local state, filters entry postings (only topics/bundles), skips when user is not connected.
- **`test/controllers/hey_emails_controller_test.rb`** — `PATCH #triage` creates a `TaskAssignment(source: :local, week_bucket: "sometime")` and stamps `triaged_at`; `PATCH #dismiss` stamps `dismissed_at` without creating a task; both respond Turbo Stream with a `<turbo-stream action="remove">` targeting `hey_email_<id>`; sync-race returns `:no_content`; cross-user access is a no-op.

## Acceptance criteria

- [ ] `bin/rails db:migrate` runs clean and creates `hey_emails` with all indexes.
- [ ] `SyncHeyEmailsJob.perform_now(User.first.id)` against a real connected account populates `HeyEmail` rows across Imbox / Reply Later / Set Aside, capped at 25 per folder.
- [ ] Running the job a second time does not duplicate rows and does not churn `updated_at` on rows whose display fields haven't changed.
- [ ] Rows with `triaged_at` or `dismissed_at` set are preserved on subsequent syncs even if they disappear from HEY.
- [ ] Visiting `/triage` renders three sections (Imbox / Reply Later / Set Aside) with newest-first ordering; empty sections disappear.
- [ ] Clicking "This week" on a row removes it via Turbo Stream, creates a new `TaskAssignment` (`source: :local`, `week_bucket: "sometime"`) with matching title, and the new task appears in the week view Sometime column.
- [ ] Clicking "Dismiss" removes the row via Turbo Stream and stamps `dismissed_at` without creating a task.
- [ ] Morning ritual step 2 shows a footnote with the correct count and links to `/triage`, and the footnote disappears when `for_triage.count == 0`.
- [ ] Settings shows a "Triage inbox" sub-action under the HEY row when connected.
- [ ] Disconnecting HEY from Settings clears `hey_emails` for the user (`count == 0`) before wiping tokens.
- [ ] `bin/rails test` is green — all 17 new tests pass, existing suite unaffected.
- [ ] **Network proof of read-only**: running the triage flow while tailing `log/development.log` shows zero `POST` / `PATCH` / `DELETE` requests to `hey.com`. Only `GET`s.

## Out of scope

- **Any write-back to HEY** — archive, mark read, move folders, reply. All write actions happen in HEY itself.
- **Un-dismissing from within Daybreak.** To reset, act on the email in HEY (the next sync won't resurrect a dismissed row unless its external_id changes, which HEY won't do).
- **Pagination beyond 25 per folder.** Triage is for recent arrivals, not archive archaeology.
- **Email search, filtering, or body rendering.** The subject link opens HEY in a new tab for anything deeper.
- **Attachments.**
- **Surfacing emails inside the day view or week Kanban directly.** Triage is a ritual artifact, not a fourth planning view.
- **Notifications about new email.** Ambient email-awareness is the exact anxiety Daybreak avoids.
- **Multi-account / family HEY Email support.**
