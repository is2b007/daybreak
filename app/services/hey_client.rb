require "net/http"
require "json"
require "securerandom"
require "digest"
require "base64"

class HeyClient
  extend HttpTimeouts
  include HttpTimeouts

  BASE_AUTH_URL = "https://app.hey.com"
  BASE_API_URL  = "https://app.hey.com"

  # Public OAuth client ID — shared by all HEY API consumers.
  # HEY uses PKCE instead of a client_secret, so no registration is required.
  CLIENT_ID  = "khMWSVDVSq78oyKA3KtxmYRv"
  INSTALL_ID = "daybreak"

  class AuthError < StandardError; end

  RECORDINGS_MAX_PAGES = 20

  # True unless the last recordings walk stopped early (failed page or page cap).
  def recordings_complete?
    @recordings_complete != false
  end

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
    response = http_post_form(uri, {
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
    response = http_post_form(uri, {
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

    response = http_start(uri) { |http| http.request(request) }
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
    fetch_recordings_pages("/calendars/#{calendar_id}/recordings.json#{query}")
  end

  # Returns timed calendar recordings from all calendars in a date window.
  # Uses GET /calendars/:id/recordings.json (same as hey-cli GetCalendarRecordings), not events.json.
  # `starts_on` / `ends_on` should be ISO8601 date strings (e.g. "2026-04-08").
  # nil if calendars.json failed (do not prune). [] if the user has no calendars/events.
  def calendar_events(starts_on:, ends_on:)
    @recordings_complete = true
    raw_cals = get("/calendars.json")
    if raw_cals.nil?
      @recordings_complete = false
      return nil
    end

    calendars_data = normalize_calendars_list(raw_cals)
    return [] unless calendars_data.is_a?(Array)

    calendars_data.flat_map do |cal|
      cid = cal["id"].to_s
      color = cal["color"].presence
      raw = calendar_recordings(cid, starts_on: starts_on, ends_on: ends_on)
      if raw.nil?
        @recordings_complete = false
        next []
      end
      @recordings_complete &&= (@last_recordings_complete != false)
      flatten_calendar_recordings(raw, calendar_id: cid, color: color)
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
    @recordings_complete = true
    raw_cals = get("/calendars.json")
    if raw_cals.nil?
      @recordings_complete = false
      return nil
    end

    cals = normalize_calendars_list(raw_cals)
    return [] unless cals.is_a?(Array)

    cal_id = personal_calendar_id(cals)
    if cal_id.blank?
      Rails.logger.warn("HeyClient#todos: no personal calendar in HEY list for user #{@user.id}")
      return []
    end

    starts_on = 2.years.ago.to_date.iso8601
    ends_on = 1.year.from_now.to_date.iso8601
    raw = calendar_recordings(cal_id.to_s, starts_on: starts_on, ends_on: ends_on)
    return nil if raw.nil?

    @recordings_complete = (@last_recordings_complete != false)
    recordings_calendar_todos(raw)
  end

  # Week period: recurring events are expanded into the occurrences that fall
  # inside the week. Recordings list a series once, on the day it was created.
  def calendar_week(date)
    get("/calendar/weeks/#{date}.json")
  end

  def calendar_week_events(date)
    raw = calendar_week(date)
    return nil if raw.nil?

    flatten_calendar_period(raw)
  end

  # +starts_at+ is a bare YYYY-MM-DD. An RFC 3339 midnight can land on the
  # previous day once HEY casts it in the user's zone (hey-sdk CalendarTodos).
  def create_todo(title:, starts_at: nil, ends_at: nil)
    inner = {
      title: title.to_s,
      starts_at: coerce_todo_date(starts_at) || Date.current.iso8601
    }
    post("/calendar/todos.json", { "calendar_todo" => inner })
  end

  def update_todo(todo_id, title: nil, starts_at: nil, focused: nil)
    changes = {}
    changes[:title] = title.to_s if title.present?
    changes[:starts_at] = coerce_todo_date(starts_at) if starts_at.present?
    changes[:focused] = focused unless focused.nil?
    return nil if changes.empty?

    patch("/calendar/todos/#{todo_id}.json", { "calendar_todo" => changes })
  end

  def delete_todo(todo_id)
    delete("/calendar/todos/#{todo_id}.json")
  end

  def complete_todo(todo_id)
    post("/calendar/todos/#{todo_id}/completions.json")
  end

  def uncomplete_todo(todo_id)
    delete("/calendar/todos/#{todo_id}/completions.json")
  end

  # Normalizes GetCalendarRecordings JSON (map of type => arrays) into flat event-like hashes.
  def flatten_calendar_recordings(raw, calendar_id:, color: nil)
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
        next if rid.nil?

        cid = calendar_id.presence
        if cid.blank? && rec["calendar"].is_a?(Hash)
          cid = rec.dig("calendar", "id").to_s.presence
        end

        merged = rec.merge(
          "id" => rid.to_s,
          "hey_calendar_id" => cid
        )
        merged["calendar_color"] = color if color.present?
        stamp_hey_event_content!(merged)
        stamp_hey_event_identity!(merged)
        rows << merged
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

  # Week/day period payload: { starts_at, ends_at, kind, recordings: { "Calendar::Event" => [...] } }
  def flatten_calendar_period(raw)
    return [] if raw.blank?
    return [] unless raw.is_a?(Hash)

    data = raw.stringify_keys
    recordings = data["recordings"] || data
    return [] unless recordings.is_a?(Hash) || recordings.is_a?(Array)

    if recordings.is_a?(Hash)
      event_keys = recordings.keys.select { |k| k.to_s.match?(/event/i) && !k.to_s.match?(/todo/i) }
      subset = event_keys.any? ? recordings.slice(*event_keys) : recordings
      rows = flatten_calendar_recordings(subset, calendar_id: nil)
      rows.reject! { |r| r["type"].to_s.match?(/todo/i) } if event_keys.empty?
      rows
    else
      flatten_calendar_recordings(recordings, calendar_id: nil)
    end
  end

  # Official writes (hey-sdk CalendarEventsService): form to /calendar/events.json
  # with calendar_event[set_time_zone]=1 so zone names are not dropped.
  def update_calendar_event(calendar_id:, event_id:, title: nil, starts_at: nil, ends_at: nil, all_day: nil, time_zone: nil, description: nil, location: nil, url: nil, entry_id: nil)
    return nil if starts_at.blank? || ends_at.blank?

    ref = parse_event_ref(event_id)
    tz = time_zone.to_s.presence || @user.timezone.presence || "UTC"
    pairs = calendar_event_form_pairs(
      calendar_id: calendar_id,
      title: title,
      starts_at: starts_at,
      ends_at: ends_at,
      all_day: all_day,
      time_zone: tz,
      description: description,
      location: location,
      url: url,
      entry_id: entry_id,
      occurrence: ref[:occurrence]
    )
    path = if ref[:occurrence]
      "/calendar/events/#{ref[:series_id]}/occurrences/#{ref[:date]}.json"
    else
      "/calendar/events/#{ref[:series_id]}.json"
    end
    meta = form_request(:patch, path, pairs)
    return nil unless form_write_ok?(meta)

    extract_event_id_from_form_meta(meta).presence || event_id.to_s
  end

  def delete_calendar_event(calendar_id: nil, event_id:)
    ref = parse_event_ref(event_id)
    path = if ref[:occurrence]
      "/calendar/events/#{ref[:series_id]}/occurrences/#{ref[:date]}.json?apply_to_future=false"
    else
      "/calendar/events/#{ref[:series_id]}.json"
    end
    data = delete(path)
    return true if calendar_delete_ok?(data)

    # Last-resort nested-path delete for leftover ids from older clients.
    return false if calendar_id.blank?

    calendar_delete_ok?(delete("/calendars/#{calendar_id}/events/#{ref[:series_id]}.json"))
  end

  def create_calendar_event(calendar_id:, title:, starts_at:, ends_at:, all_day: false, time_zone: nil)
    create_timed_calendar_event_form(
      calendar_id: calendar_id,
      title: title,
      local_start: starts_at,
      local_end: ends_at,
      time_zone: time_zone || @user.timezone.presence || "UTC",
      all_day: all_day
    )
  end

  def create_timed_calendar_event_form(calendar_id:, title:, local_start:, local_end:, time_zone:, all_day: false)
    pairs = calendar_event_form_pairs(
      calendar_id: calendar_id,
      title: title,
      starts_at: local_start,
      ends_at: local_end,
      all_day: all_day,
      time_zone: time_zone
    )
    meta = form_request(:post, "/calendar/events.json", pairs)
    extract_event_id_from_form_meta(meta)
  end

  def delete_calendar_event_form(event_id)
    delete_calendar_event(event_id: event_id)
  end

  # Official calendar delete first; leftover sometime-todo mirrors fall back to todo delete.
  def delete_timebox_mirror_remote_id(remote_id)
    return if remote_id.blank?

    cal_ok = false
    begin
      cal_ok = delete_calendar_event(event_id: remote_id)
    rescue StandardError
      cal_ok = false
    end
    return if cal_ok

    begin
      delete_todo(remote_id)
    rescue StandardError
      nil
    end
  end

  # Habits

  def complete_habit(day, habit_id)
    post("/calendar/days/#{day}/habits/#{habit_id}/completions.json")
  end

  # Time tracking

  def current_time_track
    get("/calendar/ongoing_time_track.json", allow: [ 404 ])
  end

  # HEY ignores the start body and starts a track with defaults. 409 means a
  # track is already running — adopt GET /calendar/ongoing_time_track.json.
  def start_time_track(title: nil)
    data = post("/calendar/ongoing_time_track.json", allow: [ 409 ])
    return current_time_track if @last_status_code == 409
    return data if data.is_a?(Hash) && data["id"].present?

    current_time_track || data
  end

  def stop_time_track(time_track_id, category_title: nil)
    inner = { ends_at: Time.current.iso8601 }
    inner[:category_title] = category_title if category_title.present?
    put("/calendar/time_tracks/#{time_track_id}.json", { "calendar_time_track" => inner })
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
    fetch_box("/laterbox.json")
  end

  def set_aside
    fetch_box("/asidebox.json")
  end

  def feed
    fetch_box("/feedbox.json")
  end

  def paper_trail
    fetch_box("/trailbox.json")
  end

  private

  # Returns postings from a BoxShowResponse, following next_history_url or a
  # same-origin Link: rel=next header (geared_pagination) until +max_postings+.
  # Canonical paths per hey-sdk: /laterbox.json, /asidebox.json, /trailbox.json.
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
      nxt ||= next_path_from_link_header(@last_link_header)
      break if nxt.blank?

      next_path = path_from_hey_url(nxt) || nxt
      break if next_path.blank?
    end
    all.first(max_postings)
  end

  # Walks Link: rel=next the way GetCalendarRecordingsPage does (hey-sdk #125).
  # nil if the first page fails; a Hash/Array of recordings otherwise.
  # Sets @last_recordings_complete to false when the page cap is hit with more remaining.
  def fetch_recordings_pages(initial_path, max_pages: RECORDINGS_MAX_PAGES)
    @last_recordings_complete = true
    merged = nil
    next_path = initial_path
    pages = 0
    loop do
      data = get(next_path)
      if data.nil?
        if merged.nil?
          @last_recordings_complete = false
          return nil
        end
        @last_recordings_complete = false
        break
      end

      merged = merge_recordings_page(merged, data)
      pages += 1
      nxt = next_path_from_link_header(@last_link_header)
      break if nxt.blank?

      if pages >= max_pages
        @last_recordings_complete = false
        break
      end

      next_path = path_from_hey_url(nxt) || nxt
      break if next_path.blank?
    end
    merged
  end

  def merge_recordings_page(acc, page)
    return page if acc.nil?
    return acc if page.blank?

    if acc.is_a?(Hash) && page.is_a?(Hash)
      page.each do |key, value|
        next unless value.is_a?(Array)

        acc[key] = Array(acc[key]) + value
      end
      acc
    elsif acc.is_a?(Array) && page.is_a?(Array)
      acc + page
    else
      acc
    end
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

  def get(path, allow: [])
    request(:get, path, allow: allow)
  end

  def post(path, body = nil, allow: [])
    request(:post, path, body, allow: allow)
  end

  def put(path, body, allow: [])
    request(:put, path, body, allow: allow)
  end

  def patch(path, body, allow: [])
    request(:patch, path, body, allow: allow)
  end

  def delete(path, allow: [])
    request(:delete, path, allow: allow)
  end

  def request(method, path, body = nil, allow: [])
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

    response = http_start(uri) { |http| http.request(req) }
    @last_status_code = response.code.to_i
    @last_link_header = response["Link"]

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
      refresh_and_retry!(method, path, body, allow: allow)
    else
      return nil if allow.include?(@last_status_code)

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

  def refresh_and_retry!(method, path, body, allow: [])
    perform_token_refresh!
    request(method, path, body, allow: allow)
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
    { code: 0, location: nil, body: nil, unauthorized: false, success: false }
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

    res = http_start(uri) { |http| http.request(req) }
    code = res.code.to_i
    {
      code: code,
      location: res["Location"],
      body: res.body.to_s,
      unauthorized: res.is_a?(Net::HTTPUnauthorized),
      success: res.is_a?(Net::HTTPSuccess) || [ 302, 303 ].include?(code)
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

  def extract_json_calendar_event_id(data)
    return nil unless data.is_a?(Hash)

    data["id"]&.to_s || data.dig("calendar_event", "id")&.to_s || data.dig("recording", "id")&.to_s
  end

  def extract_event_id_from_form_meta(meta)
    return nil unless form_write_ok?(meta)

    body = meta[:body].to_s.strip
    if body.present?
      parsed = JSON.parse(body) rescue nil
      id = extract_json_calendar_event_id(parsed)
      return id if id.present?
    end
    extract_form_redirect_event_id(meta)
  end

  def form_write_ok?(meta)
    return false if meta.nil?

    code = meta[:code].to_i
    meta[:success] == true || (code >= 200 && code < 300) || [ 302, 303 ].include?(code)
  end

  # JSON DELETE is 204 with an empty body (`request` returns {}). Failures return nil.
  def calendar_delete_ok?(data)
    return true if @last_status_code.to_i.between?(200, 299)

    data.is_a?(Hash)
  end

  def calendar_event_form_pairs(calendar_id:, title:, starts_at:, ends_at:, all_day:, time_zone:, description: nil, location: nil, url: nil, entry_id: nil, occurrence: false)
    tz = time_zone.to_s.presence || "UTC"
    ls = starts_at
    le = ends_at || starts_at
    pairs = [
      [ "calendar_event[calendar_id]", calendar_id.to_s ],
      [ "calendar_event[summary]", title.to_s ],
      [ "calendar_event[starts_at]", date_only(ls) ],
      [ "calendar_event[ends_at]", date_only(le) ]
    ]
    if all_day
      pairs << [ "calendar_event[all_day]", "1" ]
    else
      pairs << [ "calendar_event[all_day]", "0" ]
      pairs << [ "calendar_event[starts_at_time]", clock_time(ls) ]
      pairs << [ "calendar_event[ends_at_time]", clock_time(le) ]
      pairs << [ "calendar_event[set_time_zone]", "1" ]
      pairs << [ "calendar_event[starts_at_time_zone_name]", tz ]
      pairs << [ "calendar_event[ends_at_time_zone_name]", tz ]
    end
    # HEY clears notes/location/link/entry when they are omitted (hey-sdk EventContentParams).
    pairs << [ "calendar_event[description]", description.to_s ]
    pairs << [ "calendar_event[location]", location.to_s ]
    pairs << [ "calendar_event[url]", url.to_s ]
    pairs << [ "calendar_event[entry_id]", entry_id.to_s ]
    if occurrence
      pairs << [ "apply_to_future", "0" ]
      pairs << [ "repeat_frequency", "custom" ]
    end
    pairs
  end

  def date_only(value)
    return value.to_date.iso8601 if value.respond_to?(:to_date)

    value.to_s[0, 10]
  end

  def clock_time(value)
    return "#{value.strftime("%H:%M")}:00" if value.respond_to?(:strftime)

    str = value.to_s
    if (m = str.match(/T(\d{2}:\d{2})/))
      return "#{m[1]}:00"
    end

    "00:00:00"
  end

  def coerce_todo_date(value)
    return nil if value.blank?
    return value if value.is_a?(String) && value.match?(/\A\d{4}-\d{2}-\d{2}\z/)
    return value.to_date.iso8601 if value.respond_to?(:to_date)

    Date.iso8601(value.to_s).iso8601
  rescue ArgumentError
    value.to_s[0, 10]
  end

  EVENT_OCCURRENCE_REF = /\A(\d+):(\d{4}-\d{2}-\d{2})\z/
  EVENT_OCCURRENCE_ID = /\A(\d+)_(\d{4}-\d{2}-\d{2})\z/

  def parse_event_ref(event_id)
    str = event_id.to_s
    if str =~ EVENT_OCCURRENCE_REF || str =~ EVENT_OCCURRENCE_ID
      { series_id: ::Regexp.last_match(1), date: ::Regexp.last_match(2), occurrence: true }
    else
      { series_id: str, date: nil, occurrence: false }
    end
  end

  def stamp_hey_event_identity!(rec)
    occ = rec["occurrence_id"] || rec["occurrenceId"]
    if occ.to_s =~ EVENT_OCCURRENCE_ID
      rec["id"] = "#{::Regexp.last_match(1)}:#{::Regexp.last_match(2)}"
      return rec
    end

    parent = rec["parent_id"] || rec["parentId"]
    parent ||= rec.dig("parent", "id") if rec["parent"].is_a?(Hash)
    series_id = (parent.presence || rec["id"]).to_s
    starts = rec["starts_at"] || rec["startsAt"]

    if occ.present? && series_id.present? && starts.present?
      date = occurrence_calendar_date(starts)
      rec["id"] = "#{series_id}:#{date}" if date
    end
    rec
  end

  def stamp_hey_event_content!(rec)
    desc = rec["description"] || rec["notes"]
    rec["description"] = desc.to_s if desc.present?

    loc = rec["location"]
    rec["location"] = loc.to_s if loc.present?

    url = rec["url"] || rec["join_link"] || rec["joinLink"] || rec["link"]
    rec["url"] = url.to_s if url.present?

    entry = rec["entry_id"] || rec["entryId"]
    entry ||= rec.dig("attached_entry", "id") if rec["attached_entry"].is_a?(Hash)
    entry ||= rec.dig("attachedEntry", "id") if rec["attachedEntry"].is_a?(Hash)
    rec["entry_id"] = entry.to_s if entry.present?

    rec
  end

  # Occurrence paths use the event's civil date. A UTC parse of an evening
  # offset timestamp (e.g. 2026-04-15T23:00:00-05:00) would become the next day.
  def occurrence_calendar_date(starts)
    str = starts.to_s
    return str if str.match?(/\A\d{4}-\d{2}-\d{2}\z/)
    return str[0, 10] if str.match?(/\A\d{4}-\d{2}-\d{2}T.+(?:[+-]\d{2}:\d{2}|[+-]\d{4})\z/)

    zone = Time.find_zone(@user.timezone.presence) || Time.zone
    zone.parse(str)&.to_date&.iso8601
  rescue ArgumentError, TypeError
    str[0, 10] if str.match?(/\A\d{4}-\d{2}-\d{2}/)
  end

  def next_path_from_link_header(link)
    return nil if link.blank?

    part = link.to_s.split(",").map(&:strip).find do |p|
      p.include?('rel="next"') || p.include?("rel=next") || p.include?("rel='next'")
    end
    return nil unless part

    url = part[/<([^>]+)>/, 1]
    path_from_hey_url(url) || url
  end
end
