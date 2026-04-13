require "net/http"
require "json"
require "securerandom"
require "digest"
require "base64"

class HeyClient
  BASE_AUTH_URL = "https://app.hey.com"
  BASE_API_URL  = "https://app.hey.com"

  # Public OAuth client ID — shared by all HEY API consumers.
  # HEY uses PKCE instead of a client_secret, so no registration is required.
  CLIENT_ID  = "khMWSVDVSq78oyKA3KtxmYRv"
  INSTALL_ID = "daybreak"

  class AuthError < StandardError; end

  # OAuth flow — class methods

  def self.generate_code_verifier
    Base64.urlsafe_encode64(SecureRandom.random_bytes(32), padding: false)
  end

  def self.generate_code_challenge(verifier)
    digest = Digest::SHA256.digest(verifier)
    Base64.urlsafe_encode64(digest, padding: false)
  end

  def self.authorize_url(redirect_uri, code_challenge:, state:)
    params = {
      client_id: CLIENT_ID,
      grant_type: "authorization_code",
      redirect_uri: redirect_uri,
      state: state,
      code_challenge: code_challenge,
      code_challenge_method: "S256",
      install_id: INSTALL_ID
    }
    "#{BASE_AUTH_URL}/oauth/authorizations/new?#{params.to_query}"
  end

  def self.exchange_code(code, redirect_uri, code_verifier:)
    uri = URI("#{BASE_AUTH_URL}/oauth/tokens")
    response = Net::HTTP.post_form(uri, {
      grant_type: "authorization_code",
      client_id: CLIENT_ID,
      code: code,
      redirect_uri: redirect_uri,
      code_verifier: code_verifier,
      install_id: INSTALL_ID
    })

    raise AuthError, "HEY token exchange failed: #{response.code}" unless response.is_a?(Net::HTTPSuccess)
    JSON.parse(response.body)
  end

  def self.refresh_token(refresh_token)
    uri = URI("#{BASE_AUTH_URL}/oauth/tokens")
    response = Net::HTTP.post_form(uri, {
      grant_type: "refresh_token",
      client_id: CLIENT_ID,
      refresh_token: refresh_token,
      install_id: INSTALL_ID
    })

    raise AuthError, "HEY token refresh failed: #{response.code}" unless response.is_a?(Net::HTTPSuccess)
    JSON.parse(response.body)
  end

  def self.fetch_identity(access_token)
    uri = URI("#{BASE_AUTH_URL}/identity.json")
    request = Net::HTTP::Get.new(uri)
    request["Authorization"] = "Bearer #{access_token}"
    request["User-Agent"] = user_agent

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(request) }
    raise AuthError, "HEY identity fetch failed: #{response.code}" unless response.is_a?(Net::HTTPSuccess)
    JSON.parse(response.body)
  end

  # HEY uses a public client ID with PKCE — no registration or credentials needed.
  def self.configured?
    true
  end

  def self.user_agent
    "Daybreak (kosta@daybreak.app)"
  end

  def initialize(user)
    @user = user
  end

  # Calendar

  def calendars
    get("/calendars.json")
  end

  def calendar_recordings(calendar_id)
    get("/calendars/#{calendar_id}/recordings.json")
  end

  # Returns calendar events from all of the user's calendars within a date window.
  # `starts_on` / `ends_on` should be ISO8601 date strings (e.g. "2026-04-08").
  def calendar_events(starts_on:, ends_on:)
    calendars_data = calendars
    return [] unless calendars_data.is_a?(Array)

    calendars_data.flat_map do |cal|
      query = URI.encode_www_form(starts_on: starts_on, ends_on: ends_on)
      events = get("/calendars/#{cal['id']}/events.json?#{query}")
      next [] unless events.is_a?(Array)

      cid = cal["id"].to_s
      events.map { |e| e.is_a?(Hash) ? e.merge("hey_calendar_id" => cid) : e }
    end
  end

  # Todos — aligned with hey-sdk CalendarTodosService.Create:
  # POST /calendar/todos.json, body { "calendar_todo" => { "title", "starts_at" } }.
  # Generated hey-sdk client has no calendar_id on Create; reschedule is delete + create.

  def todos
    get("/calendar/todos.json")
  end

  # +starts_at+ may be Time or Date; serialized as ISO8601 (hey-sdk OpenAPI: date or time string).
  def create_todo(title:, starts_at: nil, ends_at: nil)
    inner = {
      title: title.to_s,
      starts_at: starts_at.respond_to?(:iso8601) ? starts_at.iso8601 : starts_at.to_s
    }.compact
    # Non-standard field; HEY may ignore. Omitted if not set.
    inner[:ends_at] = ends_at.iso8601 if ends_at.respond_to?(:iso8601)
    post("/calendar/todos.json", { "calendar_todo" => inner })
  end

  def delete_todo(todo_id)
    delete("/calendar/todos/#{todo_id}")
  end

  def complete_todo(todo_id)
    post("/calendar/todos/#{todo_id}/completions.json")
  end

  def uncomplete_todo(todo_id)
    delete("/calendar/todos/#{todo_id}/completions.json")
  end

  # Calendar events — read via /calendars/:id/events.json (Daybreak sync).
  # hey-sdk OpenAPI exposes ListCalendars + GetCalendarRecordings, not event PATCH/DELETE;
  # these mutations use the same /calendars/:id/events/:id.json shape as the HEY web app.
  def update_calendar_event(calendar_id:, event_id:, title: nil, starts_at: nil, ends_at: nil, all_day: nil)
    attrs = {}.tap do |h|
      h[:title] = title if title.present?
      h[:starts_at] = starts_at.iso8601 if starts_at.respond_to?(:iso8601)
      h[:ends_at] = ends_at.iso8601 if ends_at.respond_to?(:iso8601)
      h[:all_day] = all_day unless all_day.nil?
    end
    return nil if attrs.empty?

    patch("/calendars/#{calendar_id}/events/#{event_id}.json", { "calendar_event" => attrs })
  end

  def delete_calendar_event(calendar_id:, event_id:)
    delete("/calendars/#{calendar_id}/events/#{event_id}.json")
  end

  def create_calendar_event(calendar_id:, title:, starts_at:, ends_at:, all_day: false)
    attrs = {
      title: title.to_s,
      starts_at: starts_at.respond_to?(:iso8601) ? starts_at.iso8601 : starts_at.to_s,
      ends_at: ends_at.respond_to?(:iso8601) ? ends_at.iso8601 : ends_at.to_s,
      all_day: all_day
    }
    post("/calendars/#{calendar_id}/events.json", { "calendar_event" => attrs })
  end

  # Habits

  def complete_habit(day, habit_id)
    post("/calendar/days/#{day}/habits/#{habit_id}/completions.json")
  end

  # Time tracking

  def current_time_track
    get("/calendar/ongoing_time_track.json")
  end

  def start_time_track(title: nil)
    post("/calendar/ongoing_time_track.json", { title: title }.compact)
  end

  def stop_time_track(time_track_id)
    put("/calendar/time_tracks/#{time_track_id}.json", { ends_at: Time.current.iso8601 })
  end

  # Journal

  def journal_entry(day)
    get("/calendar/days/#{day}/journal_entry.json")
  end

  # Body shape must match HEY API / hey-sdk JournalService.Update:
  #   { "calendar_journal_entry" => { "content" => "..." } }
  # (see https://github.com/basecamp/hey-sdk/blob/main/go/pkg/hey/journal.go)
  def write_journal(day, content)
    patch("/calendar/days/#{day}/journal_entry.json", {
      "calendar_journal_entry" => { "content" => content.to_s }
    })
  end

  # Email triage (read-only)
  #
  # HEY's box endpoints return a BoxShowResponse wrapper:
  #   { id:, kind:, name:, postings: [Posting, ...] }
  # Posting shape (polymorphic by `kind`: "topic" | "bundle" | "entry"):
  #   { id:, kind:, name: (subject), summary: (snippet), app_url:,
  #     observed_at:, created_at:, updated_at:, seen:,
  #     creator: { name:, email_address: } }

  def imbox
    fetch_box("/imbox.json")
  end

  def reply_later
    fetch_box("/reply_later.json")
  end

  def set_aside
    fetch_box("/set_aside.json")
  end

  def feed
    fetch_box("/feedbox.json")
  end

  def paper_trail
    fetch_box("/paper_trail.json")
  end

  private

  # Returns postings from a BoxShowResponse, following next_history_url until +max_postings+.
  # Canonical paths per hey-sdk openapi (not /laterbox.json etc.).
  # nil on first-request failure; [] if the box is empty.
  def fetch_box(initial_path, max_postings: 200)
    all = []
    next_path = initial_path
    loop do
      data = get(next_path)
      if data.nil?
        return nil if all.empty?
        break
      end

      data = data["box"] if data.is_a?(Hash) && data["box"].is_a?(Hash)
      break unless data.is_a?(Hash)

      chunk = data["postings"]
      chunk = chunk.is_a?(Array) ? chunk : []
      all.concat(chunk)
      break if all.size >= max_postings

      nxt = data["next_history_url"].presence
      break if nxt.blank?

      next_path = path_from_hey_url(nxt) || break
    end
    all.first(max_postings)
  end

  def path_from_hey_url(url)
    u = URI.parse(url.to_s)
    return nil unless u.host&.end_with?("hey.com")

    path = u.path.to_s
    path += "?#{u.query}" if u.query.present?
    path.presence
  end

  def get(path)
    request(:get, path)
  end

  def post(path, body = nil)
    request(:post, path, body)
  end

  def put(path, body)
    request(:put, path, body)
  end

  def patch(path, body)
    request(:patch, path, body)
  end

  def delete(path)
    request(:delete, path)
  end

  def request(method, path, body = nil)
    ensure_fresh_token!

    uri = URI("#{BASE_API_URL}#{path}")

    req = case method
    when :get    then Net::HTTP::Get.new(uri)
    when :post   then Net::HTTP::Post.new(uri)
    when :put    then Net::HTTP::Put.new(uri)
    when :patch  then Net::HTTP::Patch.new(uri)
    when :delete then Net::HTTP::Delete.new(uri)
    end

    req["Authorization"] = "Bearer #{@user.hey_access_token}"
    req["Content-Type"]  = "application/json"
    req["Accept"]        = "application/json"
    req["User-Agent"]    = self.class.user_agent

    req.body = body.to_json if body

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }

    case response
    when Net::HTTPSuccess
      body_str = response.body.to_s
      # PATCH/PUT often return 204 or empty JSON; callers treat nil as failure.
      if body_str.strip.empty?
        return nil if method == :get

        return {}
      end

      JSON.parse(body_str)
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
    # Use with_lock to prevent concurrent refresh races under concurrent job syncs.
    @user.with_lock do
      return if @user.reload.hey_token_fresh?

      data = self.class.refresh_token(@user.hey_refresh_token)
      expires_in = data["expires_in"]&.to_i
      expires_at = expires_in&.positive? ? expires_in.seconds.from_now : 2.weeks.from_now

      @user.update!(
        hey_access_token: data["access_token"],
        hey_refresh_token: data["refresh_token"].presence || @user.hey_refresh_token,
        hey_token_expires_at: expires_at
      )
    end
  end

  def refresh_and_retry!(method, path, body)
    perform_token_refresh!
    request(method, path, body)
  rescue AuthError
    raise AuthError, "HEY session expired. Reconnect from Settings."
  rescue StandardError => e
    Rails.logger.error("HEY API transport error: #{e.class} #{e.message}")
    raise
  end
end
