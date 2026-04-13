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

  # HEY returns CalendarListPayload: { "calendars" => [ { "calendar" => { "id", "name", ... } } ] }
  # (same shape hey-cli unwraps in internal/cmd/sdk.go). Bare arrays are still accepted for tests.
  def calendars
    normalize_calendars_list(get("/calendars.json"))
  end

  def calendar_recordings(calendar_id, starts_on: nil, ends_on: nil)
    query = if starts_on.present? && ends_on.present?
      "?#{URI.encode_www_form(starts_on: starts_on, ends_on: ends_on)}"
    else
      ""
    end
    get("/calendars/#{calendar_id}/recordings.json#{query}")
  end

  # Returns timed calendar recordings from all calendars in a date window.
  # Uses GET /calendars/:id/recordings.json (same as hey-cli GetCalendarRecordings), not events.json.
  # `starts_on` / `ends_on` should be ISO8601 date strings (e.g. "2026-04-08").
  def calendar_events(starts_on:, ends_on:)
    calendars_data = calendars
    return [] unless calendars_data.is_a?(Array)

    calendars_data.flat_map do |cal|
      cid = cal["id"].to_s
      raw = calendar_recordings(cid, starts_on: starts_on, ends_on: ends_on)
      flatten_calendar_recordings(raw, calendar_id: cid)
    end
  end

  # HEY calendar id for timed events (timebox mirror, HEY event PATCH): explicit default in Settings,
  # else personal calendar (hey-cli findPersonalCalendarID).
  def calendar_id_for_timed_writes
    return @__calendar_id_timed if instance_variable_defined?(:@__calendar_id_timed)

    explicit = @user.hey_default_calendar_id.presence
    return @__calendar_id_timed = explicit if explicit.present?

    list = calendars
    @__calendar_id_timed = personal_calendar_id(list)&.to_s.presence
  end

  # Todos — list path matches hey-cli (`hey todo list`): personal calendar recordings, type Calendar::Todo.
  # POST /calendar/todos.json is for create (see #create_todo); not used for listing.

  def todos
    cals = calendars
    return [] unless cals.is_a?(Array)

    cal_id = personal_calendar_id(cals)
    if cal_id.blank?
      Rails.logger.warn("HeyClient#todos: no personal calendar in HEY list for user #{@user.id}")
      return []
    end

    starts_on = 2.years.ago.to_date.iso8601
    ends_on = 1.year.from_now.to_date.iso8601
    raw = calendar_recordings(cal_id.to_s, starts_on: starts_on, ends_on: ends_on)
    recordings_calendar_todos(raw)
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

  # Normalizes GetCalendarRecordings JSON (map of type => arrays) into flat event-like hashes.
  def flatten_calendar_recordings(raw, calendar_id:)
    rows = []
    return rows if raw.blank?

    append_recordings = lambda do |list|
      return unless list.is_a?(Array)

      list.each do |rec|
        next unless rec.is_a?(Hash)

        rec = rec.stringify_keys
        starts = rec["starts_at"] || rec["startsAt"]
        next if starts.blank?

        rid = rec["id"]
        next if rid.blank?

        rows << rec.merge(
          "id" => rid.to_s,
          "hey_calendar_id" => calendar_id
        )
      end
    end

    case raw
    when Hash
      raw.each_value { |list| append_recordings.call(list) }
    when Array
      append_recordings.call(raw)
    end

    rows.uniq { |r| [ r["hey_calendar_id"], r["id"] ] }
  end

  # Synced HEY calendar rows (drag/resize/delete in Daybreak): JSON under /calendars/:id/events…
  # hey-sdk OpenAPI documents Bearer calendar *writes* for todos (`POST /calendar/todos.json`);
  # session-only form routes like `POST /calendar/events` return 404 for OAuth clients (see debug H6).
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

  # Timed HEY calendar mirror: try hey-sdk browser form first, then JSON create (runtime: OAuth gets 404 on form — debug H7).
  # Form matches go/pkg/hey/calendar_events.go; JSON matches #create_calendar_event for Bearer.
  def create_timed_calendar_event_form(calendar_id:, title:, local_start:, local_end:, time_zone:)
    tz = time_zone.to_s.presence || "UTC"
    ls = local_start
    le = local_end
    starts_date = ls.to_date.iso8601
    ends_date = le.to_date.iso8601
    form_pairs = [
      [ "calendar_event[calendar_id]", calendar_id.to_s ],
      [ "calendar_event[summary]", title.to_s ],
      [ "calendar_event[starts_at]", starts_date ],
      [ "calendar_event[ends_at]", ends_date ],
      [ "calendar_event[all_day]", "0" ],
      [ "calendar_event[starts_at_time]", "#{ls.strftime("%H:%M")}:00" ],
      [ "calendar_event[ends_at_time]", "#{le.strftime("%H:%M")}:00" ],
      [ "calendar_event[starts_at_time_zone_name]", tz ],
      [ "calendar_event[ends_at_time_zone_name]", tz ]
    ]
    meta = form_request(:post, "/calendar/events", form_pairs)
    id = extract_form_redirect_event_id(meta)
    return id if id.present?

    json_body = {
      "calendar_event" => {
        "title" => title.to_s,
        "starts_at" => ls.iso8601,
        "ends_at" => le.iso8601,
        "all_day" => false
      }
    }
    jmeta = json_post_with_meta("/calendars/#{calendar_id}/events.json", json_body)
    return nil unless jmeta[:success]

    extract_json_calendar_event_id(jmeta[:json])
  end

  def delete_calendar_event_form(event_id)
    meta = form_request(:delete, "/calendar/events/#{event_id}", nil)
    code = meta[:code].to_i
    code == 302 || code == 303 || (code >= 200 && code < 300)
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
  # `content` is Trix HTML (see JournalService.GetContent in hey-sdk).
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

  # Mirrors hey-cli unwrapCalendars(CalendarListPayload).
  def normalize_calendars_list(data)
    return [] if data.nil?
    return data if data.is_a?(Array)
    return [] unless data.is_a?(Hash)

    rows = data["calendars"]
    return [] unless rows.is_a?(Array)

    rows.filter_map do |row|
      next unless row.is_a?(Hash)

      row = row.stringify_keys
      cal = row["calendar"]
      cal = row if cal.blank?
      next unless cal.is_a?(Hash)

      cal = cal.stringify_keys
      next if cal["id"].blank?

      cal = cal.transform_keys(&:to_s)
      cal["id"] = cal["id"].to_s
      cal
    end
  end

  # Mirrors hey-cli findPersonalCalendarID.
  def personal_calendar_id(calendars)
    hit = calendars.find { |c| [ true, "true", 1, "1" ].include?(c["personal"]) }
    hit ||= calendars.find { |c| (c["name"].to_s).casecmp("personal").zero? }
    hit&.dig("id")
  end

  # Extracts Calendar::Todo rows from GetCalendarRecordings JSON for SyncHeyCalendarJob.
  def recordings_calendar_todos(raw)
    return [] if raw.blank?
    return [] unless raw.is_a?(Hash)

    list = raw["Calendar::Todo"]
    return [] unless list.is_a?(Array)

    list.filter_map do |rec|
      next unless rec.is_a?(Hash)

      rec = rec.stringify_keys
      next if rec["id"].blank?

      {
        "id" => rec["id"].to_s,
        "title" => rec["title"].presence || rec["summary"].presence || "(untitled)",
        "completed" => rec["completed_at"].present? || rec["completedAt"].present?
      }
    end
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

  # Removes a timebox mirror id: form calendar delete, JSON calendar delete, then legacy todo mirrors.
  def delete_timebox_mirror_remote_id(remote_id)
    return if remote_id.blank?

    cal_ok = false
    begin
      cal_ok = delete_calendar_event_form(remote_id)
    rescue StandardError
      cal_ok = false
    end
    return if cal_ok

    cid = calendar_id_for_timed_writes
    if cid.present?
      json_del = nil
      begin
        json_del = delete_calendar_event(calendar_id: cid, event_id: remote_id)
      rescue StandardError
        json_del = nil
      end
      return unless json_del.nil?
    end

    begin
      delete_todo(remote_id)
    rescue StandardError
      nil
    end
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

  def form_request(method, path, form_pairs)
    ensure_fresh_token!
    meta = perform_form_http(method, path, form_pairs)
    if meta[:unauthorized]
      perform_token_refresh!
      meta = perform_form_http(method, path, form_pairs)
    end
    if meta[:unauthorized] || meta[:code].to_i == 401
      raise AuthError, "HEY session expired. Reconnect from Settings."
    end
    meta
  rescue AuthError
    raise
  rescue StandardError => e
    Rails.logger.error("HEY form request error: #{e.class} #{e.message}")
    { code: 0, location: nil, unauthorized: false }
  end

  def perform_form_http(method, path, form_pairs)
    uri = URI("#{BASE_API_URL}#{path}")
    req = case method
    when :post   then Net::HTTP::Post.new(uri)
    when :patch  then Net::HTTP::Patch.new(uri)
    when :delete then Net::HTTP::Delete.new(uri)
    else
      raise ArgumentError, "unsupported form method #{method.inspect}"
    end

    req["Authorization"] = "Bearer #{@user.hey_access_token}"
    req["Accept"] = "*/*"
    req["User-Agent"] = self.class.user_agent
    if form_pairs.present?
      req["Content-Type"] = "application/x-www-form-urlencoded"
      req.body = URI.encode_www_form(form_pairs)
    end

    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
    {
      code: res.code.to_i,
      location: res["Location"],
      unauthorized: res.is_a?(Net::HTTPUnauthorized)
    }
  end

  def extract_form_redirect_event_id(meta)
    location = meta[:location]
    return nil if location.blank?

    u = URI.join("#{BASE_API_URL}/", location)
    segments = u.path.to_s.chomp("/").split("/")
    segments.reverse_each do |seg|
      return seg if seg.match?(/\A\d+\z/)
    end
    nil
  end

  def json_post_with_meta(path, body)
    ensure_fresh_token!
    meta = single_json_post(path, body)
    if meta[:unauthorized]
      perform_token_refresh!
      meta = single_json_post(path, body)
    end
    if meta[:unauthorized] || meta[:code] == 401
      raise AuthError, "HEY session expired. Reconnect from Settings."
    end
    meta
  end

  def single_json_post(path, body)
    uri = URI("#{BASE_API_URL}#{path}")
    req = Net::HTTP::Post.new(uri)
    req["Authorization"] = "Bearer #{@user.hey_access_token}"
    req["Content-Type"]  = "application/json"
    req["Accept"]        = "application/json"
    req["User-Agent"]    = self.class.user_agent
    req.body = body.to_json

    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
    parsed =
      if res.is_a?(Net::HTTPSuccess)
        s = res.body.to_s.strip
        s.present? ? (JSON.parse(s) rescue nil) : {}
      end
    {
      code: res.code.to_i,
      json: parsed,
      success: res.is_a?(Net::HTTPSuccess),
      unauthorized: res.is_a?(Net::HTTPUnauthorized)
    }
  end

  def extract_json_calendar_event_id(data)
    return nil unless data.is_a?(Hash)

    data["id"]&.to_s || data.dig("calendar_event", "id")&.to_s
  end
end
