# Spec 02 — Calendar integration (Basecamp + HEY)

Wire calendar events into the week view, day timeline, and morning ritual. Right now all three places return empty arrays/hashes with `# TODO` markers.

## Context

Daybreak shows a unified view of two upstreams: **Basecamp schedule entries** (work meetings, deadlines) and **HEY Calendar events** (personal). The product spec calls for them appearing in three places:

1. **Week view** — small chips at the top of each day column
2. **Day view timeline** — positioned blocks at the right hour, with `--basecamp` or `--hey` color
3. **Morning ritual step 2** — read-only awareness ("here's what's already scheduled")

The clients (`BasecampClient`, `HeyClient`) already exist with bearer-token auth and error handling. The view partials (`weeks/_calendar_event.html.erb`, `days/_timeline.html.erb`'s event loop) are in place and expect a hash shape: `{ source:, title:, time:, start_hour:, duration_hours: }`. The plumbing in between is what's missing.

## Files that need work

| File | What's wrong |
|---|---|
| `app/services/basecamp_client.rb` | Has `schedule_entries(schedule_id)` but no method to discover schedule IDs across projects |
| `app/services/hey_client.rb` | Has `calendars` and `calendar_recordings(id)` but nothing that returns date-windowed events |
| `app/controllers/weeks_controller.rb:30-34` | `fetch_calendar_events` returns `{}` |
| `app/controllers/days_controller.rb:19-22` | `fetch_calendar_events` returns `[]` |
| `app/controllers/rituals_controller.rb:88-92` | `load_todays_schedule` returns three empty arrays |
| `app/jobs/sync_basecamp_assignments_job.rb` | Only syncs todos, not schedule entries |
| `app/jobs/sync_hey_calendar_job.rb` | Only syncs todos, not calendar events |

## Architecture

Don't fetch from APIs in the request cycle — week view loads need to be fast and offline-tolerant. Cache fetches in Solid Cache and refresh via background jobs.

### New table: `calendar_events`

```ruby
create_table :calendar_events do |t|
  t.references :user, null: false, foreign_key: true
  t.string :external_id, null: false
  t.integer :source, null: false  # enum: basecamp(0), hey(1)
  t.string :title, null: false
  t.datetime :starts_at, null: false
  t.datetime :ends_at
  t.boolean :all_day, default: false
  t.string :location
  t.text :description
  t.string :basecamp_bucket_id  # for back-linking
  t.timestamps
end

add_index :calendar_events, [:user_id, :starts_at]
add_index :calendar_events, [:external_id, :source], unique: true
```

### New model: `app/models/calendar_event.rb`

```ruby
class CalendarEvent < ApplicationRecord
  belongs_to :user

  enum :source, { basecamp: 0, hey: 1 }

  scope :for_date, ->(date) { where(starts_at: date.beginning_of_day..date.end_of_day) }
  scope :for_week, ->(week_start) {
    where(starts_at: week_start.beginning_of_day..(week_start + 6.days).end_of_day)
  }

  def time
    return "All day" if all_day
    starts_at.in_time_zone(user.timezone).strftime("%-I:%M%P")
  end

  def start_hour
    starts_at.in_time_zone(user.timezone).hour
  end

  def duration_hours
    return 1 unless ends_at
    ((ends_at - starts_at) / 1.hour).ceil
  end

  def to_view_hash
    { source: source, title: title, time: time, start_hour: start_hour, duration_hours: duration_hours }
  end
end
```

Add `has_many :calendar_events, dependent: :destroy` to `User`.

### BasecampClient additions

Basecamp's REST API uses per-project schedules. To get all events for a user, iterate the projects they have access to and pull each schedule. The result is rate-limited (50 req / 10s), so cache aggressively.

```ruby
# app/services/basecamp_client.rb

# Returns { id:, dock_url: } for each project's schedule
def schedules
  projects_data = projects
  return [] unless projects_data.is_a?(Array)

  projects_data.flat_map do |project|
    schedule = project["dock"]&.find { |d| d["name"] == "schedule" }
    next [] unless schedule&.dig("enabled")
    [{ project_id: project["id"], project_name: project["name"], schedule_id: schedule["id"] }]
  end
end

# Existing schedule_entries(schedule_id) — returns the array as-is
```

Note that `projects` and `schedule_entries` already exist. The new `schedules` helper just discovers them.

### HeyClient additions

HEY Calendar exposes events per-calendar. We need a date-windowed fetch helper:

```ruby
# app/services/hey_client.rb

def calendar_events(starts_on:, ends_on:)
  # HEY exposes /calendars/:id/events.json filtered by date range.
  # Iterate user's calendars (calendars()) and union the events.
  calendars_data = calendars
  return [] unless calendars_data.is_a?(Array)

  calendars_data.flat_map do |cal|
    events = get("/calendars/#{cal['id']}/events.json?starts_on=#{starts_on}&ends_on=#{ends_on}")
    events.is_a?(Array) ? events : []
  end
end
```

If the HEY endpoint shape differs from this assumption (the existing client only knows about `calendar_recordings`), check the HEY API docs and adjust. The shape returned must be parseable into the `CalendarEvent` columns.

### Sync jobs

Add a new job (cleaner than overloading the assignments job):

```ruby
# app/jobs/sync_calendar_events_job.rb
class SyncCalendarEventsJob < ApplicationJob
  queue_as :sync

  def perform(user_id)
    user = User.find(user_id)
    week_start = Date.current.beginning_of_week(:monday)
    week_end = week_start + 6.days

    sync_basecamp(user, week_start, week_end)
    sync_hey(user, week_start, week_end) if user.hey_connected?
  end

  private

  def sync_basecamp(user, week_start, week_end)
    client = BasecampClient.new(user)
    client.schedules.each do |schedule|
      entries = client.schedule_entries(schedule[:schedule_id])
      next unless entries.is_a?(Array)

      entries.each do |entry|
        next unless entry["starts_at"]
        starts_at = Time.parse(entry["starts_at"])
        next unless starts_at.between?(week_start.beginning_of_day, week_end.end_of_day)

        event = user.calendar_events.find_or_initialize_by(
          external_id: entry["id"].to_s,
          source: :basecamp
        )
        event.update!(
          title: entry["summary"],
          starts_at: starts_at,
          ends_at: entry["ends_at"] && Time.parse(entry["ends_at"]),
          all_day: entry["all_day"] == true,
          basecamp_bucket_id: entry.dig("bucket", "id")&.to_s
        )
      end
    end
  rescue BasecampClient::AuthError, BasecampClient::RateLimitError => e
    Rails.logger.warn("Basecamp calendar sync failed for user #{user.id}: #{e.message}")
  end

  def sync_hey(user, week_start, week_end)
    client = HeyClient.new(user)
    events = client.calendar_events(starts_on: week_start.iso8601, ends_on: week_end.iso8601)
    return unless events.is_a?(Array)

    events.each do |evt|
      event = user.calendar_events.find_or_initialize_by(
        external_id: evt["id"].to_s,
        source: :hey
      )
      event.update!(
        title: evt["title"] || evt["summary"],
        starts_at: Time.parse(evt["starts_at"]),
        ends_at: evt["ends_at"] && Time.parse(evt["ends_at"]),
        all_day: evt["all_day"] == true
      )
    end
  rescue HeyClient::AuthError => e
    Rails.logger.warn("HEY calendar sync failed for user #{user.id}: #{e.message}")
  end
end
```

### Schedule it

Use `solid_queue`'s recurring tasks. In `config/recurring.yml`:

```yaml
production:
  sync_calendar_events:
    class: SyncCalendarEventsJob.recurring_for_all_users
    schedule: every 15 minutes
```

Or simpler: a small recurring class that enqueues per-user:

```ruby
# app/jobs/sync_calendar_events_for_all_users_job.rb
class SyncCalendarEventsForAllUsersJob < ApplicationJob
  def perform
    User.where.not(basecamp_access_token: nil).find_each do |user|
      SyncCalendarEventsJob.perform_later(user.id)
    end
  end
end
```

And reference it from `config/recurring.yml`.

Also: enqueue a sync **on first login of the day** (in `SessionsController#create` or after `current_user.record_open!`) so the user doesn't see stale data right after signing in.

### Wire it into the controllers

```ruby
# app/controllers/weeks_controller.rb
def fetch_calendar_events
  current_user.calendar_events
    .for_week(@week_start)
    .group_by { |e| e.starts_at.in_time_zone(current_user.timezone).to_date }
    .transform_values { |events| events.map(&:to_view_hash) }
end
```

```ruby
# app/controllers/days_controller.rb
def fetch_calendar_events
  current_user.calendar_events
    .for_date(@date)
    .order(:starts_at)
    .map(&:to_view_hash)
end
```

```ruby
# app/controllers/rituals_controller.rb
def load_todays_schedule
  @calendar_events = current_user.calendar_events
    .for_date(@date)
    .order(:starts_at)
    .map(&:to_view_hash)

  @basecamp_assignments = current_user.task_assignments
    .basecamp
    .incomplete
    .where("created_at > ?", 1.week.ago)
    .limit(5)
    .map { |t| { title: t.title, due_on: nil } }

  @hey_todos = current_user.task_assignments
    .hey
    .incomplete
    .where("created_at > ?", 1.week.ago)
    .limit(5)
    .map { |t| { title: t.title } }
end
```

## Acceptance criteria

- [ ] Migration runs cleanly: `bin/rails db:migrate`
- [ ] `SyncCalendarEventsJob.perform_later(user.id)` populates `calendar_events` for a real Basecamp user
- [ ] Week view shows event chips on the correct day columns
- [ ] Day view timeline shows blocks at the correct hour with the correct color (blue=basecamp, green=hey)
- [ ] Morning ritual step 2 shows today's events instead of "Wide open"
- [ ] No API calls happen during a normal request cycle
- [ ] If the user revokes Basecamp, the sync job logs the warning and doesn't crash
- [ ] Recurring schedule is set up so events refresh every ~15 min

## Out of scope

- HEY OAuth itself (Spec 03 — until that lands, HEY sync is a no-op for users with no token)
- Drag-to-timebox creating a HEY calendar event (Spec 05)
- Pruning old events (the `find_or_initialize_by` upsert is idempotent — pruning is a follow-up)
