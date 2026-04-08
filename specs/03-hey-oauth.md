# Spec 03 — HEY OAuth + token refresh

Implement the full HEY OAuth flow so users can connect their HEY account from onboarding step 3 or from Settings, and so HEY tokens refresh automatically.

## Context

Daybreak's two upstreams are Basecamp (required) and HEY (optional). Basecamp OAuth is fully implemented in `BasecampClient` and `SessionsController`. HEY is not — `HeyConnectionsController` is a stub, `HeyClient` has no OAuth class methods, and there's no token refresh.

HEY's OAuth flow uses the same 37signals Launchpad as Basecamp (`https://launchpad.37signals.com`) but with `product=hey` scope. Tokens behave the same way (2-week access, refresh tokens).

## Files that need work

| File | What's missing |
|---|---|
| `app/services/hey_client.rb` | No `authorize_url`, `exchange_code`, `refresh_token`, `fetch_identity` class methods. No `ensure_fresh_token!` instance method. No retry-on-401. |
| `app/controllers/hey_connections_controller.rb` | `new` and `create` are stubs. |
| `app/jobs/refresh_tokens_job.rb` | Only refreshes Basecamp tokens. |
| `app/views/onboarding/_step_3_hey.html.erb` | If Spec 01 hid the "Connect HEY" button, restore it once this spec lands. |
| `app/models/user.rb` | Could use a `hey_token_fresh?` helper to mirror `basecamp_token_fresh?`. |
| `config/credentials.yml.enc` | Needs `hey:` section with `client_id` and `client_secret`. |

## Implementation

### 1. Credentials

```bash
EDITOR=vim bin/rails credentials:edit
```

Add (alongside the existing `basecamp:` block):

```yaml
hey:
  client_id: <from 37signals app registration>
  client_secret: <from 37signals app registration>
```

The 37signals app registration form (the same one used for Basecamp) has a "Which 37signals products will your integration access?" section — make sure HEY is checked. If a separate app registration is required for HEY, register it.

### 2. HeyClient — class methods (mirror BasecampClient)

```ruby
# app/services/hey_client.rb

BASE_AUTH_URL = "https://launchpad.37signals.com"
BASE_API_URL = "https://hey.com/api/v1"  # existing BASE_URL — rename for clarity

def self.authorize_url(redirect_uri)
  params = {
    type: "web_server",
    client_id: credentials[:client_id],
    redirect_uri: redirect_uri,
    response_type: "code"
    # NOTE: 37signals OAuth doesn't take a `scope` param — the product is determined
    # by which products you ticked when registering the app.
  }
  "#{BASE_AUTH_URL}/authorization/new?#{params.to_query}"
end

def self.exchange_code(code, redirect_uri)
  uri = URI("#{BASE_AUTH_URL}/authorization/token")
  response = Net::HTTP.post_form(uri, {
    type: "web_server",
    client_id: credentials[:client_id],
    client_secret: credentials[:client_secret],
    redirect_uri: redirect_uri,
    code: code
  })
  raise AuthError, "HEY token exchange failed: #{response.code}" unless response.is_a?(Net::HTTPSuccess)
  JSON.parse(response.body)
end

def self.refresh_token(refresh_token)
  uri = URI("#{BASE_AUTH_URL}/authorization/token")
  response = Net::HTTP.post_form(uri, {
    type: "refresh",
    client_id: credentials[:client_id],
    client_secret: credentials[:client_secret],
    refresh_token: refresh_token
  })
  raise AuthError, "HEY token refresh failed: #{response.code}" unless response.is_a?(Net::HTTPSuccess)
  JSON.parse(response.body)
end

def self.fetch_identity(access_token)
  # Same launchpad endpoint as Basecamp — the response includes accounts for all products.
  uri = URI("#{BASE_AUTH_URL}/authorization.json")
  request = Net::HTTP::Get.new(uri)
  request["Authorization"] = "Bearer #{access_token}"
  response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(request) }
  raise AuthError, "HEY identity fetch failed: #{response.code}" unless response.is_a?(Net::HTTPSuccess)
  JSON.parse(response.body)
end

def self.credentials
  creds = Rails.application.credentials.hey
  return creds if creds.present?
  { client_id: ENV["HEY_CLIENT_ID"], client_secret: ENV["HEY_CLIENT_SECRET"] }
end

def self.configured?
  credentials[:client_id].present?
end
```

### 3. HeyClient — token refresh on 401

Mirror what `BasecampClient#request` does. The current implementation raises immediately on 401:

```ruby
def request(method, path, body = nil)
  ensure_fresh_token!
  # ...existing code...
  case response
  when Net::HTTPSuccess
    JSON.parse(response.body) if response.body.present?
  when Net::HTTPUnauthorized
    refresh_and_retry!(method, path, body)
  else
    Rails.logger.error("HEY API error: #{response.code} #{response.body}")
    nil
  end
end

def ensure_fresh_token!
  return if @user.hey_token_fresh?
  perform_token_refresh!
end

def perform_token_refresh!
  data = self.class.refresh_token(@user.hey_refresh_token)
  @user.update!(
    hey_access_token: data["access_token"],
    hey_token_expires_at: 2.weeks.from_now
  )
end

def refresh_and_retry!(method, path, body)
  perform_token_refresh!
  request(method, path, body)
rescue AuthError
  raise AuthError, "HEY session expired. Reconnect from Settings."
end
```

### 4. User model helper

```ruby
# app/models/user.rb
def hey_token_fresh?
  hey_token_expires_at.present? && hey_token_expires_at > Time.current
end
```

### 5. HeyConnectionsController

```ruby
class HeyConnectionsController < ApplicationController
  skip_before_action :require_onboarding!, only: [:create]  # so users mid-onboarding can complete the callback

  def new
    redirect_to HeyClient.authorize_url(auth_hey_callback_url), allow_other_host: true
  end

  def create
    token_data = HeyClient.exchange_code(params[:code], auth_hey_callback_url)

    current_user.update!(
      hey_access_token: token_data["access_token"],
      hey_refresh_token: token_data["refresh_token"],
      hey_token_expires_at: 2.weeks.from_now
    )

    # If the user is mid-onboarding, drop them back into step 4
    if current_user.onboarded?
      redirect_to settings_path, notice: "HEY connected."
    else
      redirect_to onboarding_path(step: 4)
    end
  rescue HeyClient::AuthError => e
    if current_user.onboarded?
      redirect_to settings_path, alert: "Couldn't connect HEY. Want to try again?"
    else
      redirect_to onboarding_path(step: 3), alert: "Couldn't connect HEY. You can skip and connect later from Settings."
    end
  end

  def destroy
    current_user.update!(
      hey_access_token: nil,
      hey_refresh_token: nil,
      hey_token_expires_at: nil
    )
    redirect_to settings_path, notice: "HEY disconnected."
  end
end
```

### 6. Restore the onboarding "Connect HEY" button

If Spec 01 hid it, undo that change. The full step 3 should be the original two-button form (`Connect HEY` + `Skip for now`). Verify clicking "Connect HEY" goes to launchpad and back through the callback.

### 7. RefreshTokensJob — also refresh HEY

```ruby
# app/jobs/refresh_tokens_job.rb
def perform
  refresh_basecamp
  refresh_hey
end

private

def refresh_basecamp
  User.where("basecamp_token_expires_at < ?", 2.days.from_now)
      .where.not(basecamp_refresh_token: nil)
      .find_each do |user|
    begin
      data = BasecampClient.refresh_token(user.basecamp_refresh_token)
      user.update!(basecamp_access_token: data["access_token"], basecamp_token_expires_at: 2.weeks.from_now)
    rescue => e
      Rails.logger.error("Basecamp token refresh failed for user #{user.id}: #{e.message}")
    end
  end
end

def refresh_hey
  User.where("hey_token_expires_at < ?", 2.days.from_now)
      .where.not(hey_refresh_token: nil)
      .find_each do |user|
    begin
      data = HeyClient.refresh_token(user.hey_refresh_token)
      user.update!(hey_access_token: data["access_token"], hey_token_expires_at: 2.weeks.from_now)
    rescue => e
      Rails.logger.error("HEY token refresh failed for user #{user.id}: #{e.message}")
    end
  end
end
```

Schedule it daily via `config/recurring.yml`.

### 8. Configured-check fallback in the UI

Mirror what the login page does for Basecamp. In `app/views/settings/show.html.erb` and `app/views/onboarding/_step_3_hey.html.erb`, only render the "Connect HEY" button if `HeyClient.configured?`. Otherwise show a small note that HEY isn't configured for this Daybreak install.

## Acceptance criteria

- [ ] `HeyClient.configured?` returns true after credentials are set
- [ ] Settings page "Connect HEY" button → launchpad → callback → "HEY connected" — round trip works
- [ ] Onboarding step 3 → "Connect HEY" → launchpad → callback → step 4 (no dead-end, `onboarded` still false until step 4 completes)
- [ ] After connection, `current_user.hey_connected?` is true and `SyncHeyCalendarJob` succeeds
- [ ] Disconnect from Settings clears tokens and the connection status flips
- [ ] Hitting a 401 inside `HeyClient` triggers a refresh and retry without surfacing an error to the user
- [ ] `RefreshTokensJob` refreshes both Basecamp and HEY tokens
- [ ] If credentials are missing, the UI gracefully shows the unconfigured state

## Out of scope

- HEY Calendar event sync logic (Spec 02)
- HEY journal write-back from sundown reflection (already wired in `SyncJournalJob` — it just needs HEY connected to actually run)
- Multi-account / family HEY support
