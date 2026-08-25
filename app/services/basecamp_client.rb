require "net/http"
require "json"

class BasecampClient
  extend HttpTimeouts
  include HttpTimeouts

  BASE_AUTH_URL = "https://launchpad.37signals.com"
  BASE_API_URL = "https://3.basecampapi.com"
  # Avatar GET may 302 to arbitrary CDNs; Bearer auth is only for these API hosts.
  API_HOSTS_WITH_BEARER = %w[3.basecampapi.com 3.basecamp.com].freeze
  # my/profile sometimes returns a direct CDN URL (no API hop); still same /people/…/avatar path shape.
  BASECAMP_AVATAR_STATIC_HOST_SUFFIX = ".basecamp-static.com".freeze

  class AuthError < StandardError; end
  class RateLimitError < StandardError; end

  def initialize(user = nil)
    @user = user
  end

  # OAuth flow

  def self.authorize_url(redirect_uri)
    params = {
      type: "web_server",
      client_id: credentials[:client_id],
      redirect_uri: redirect_uri,
      response_type: "code"
    }
    "#{BASE_AUTH_URL}/authorization/new?#{params.to_query}"
  end

  def self.exchange_code(code, redirect_uri)
    uri = URI("#{BASE_AUTH_URL}/authorization/token")
    response = http_post_form(uri, {
      grant_type: "authorization_code",
      type: "web_server",
      client_id: credentials[:client_id],
      client_secret: credentials[:client_secret],
      redirect_uri: redirect_uri,
      code: code
    })

    raise AuthError, "Token exchange failed: #{response.code}" unless response.is_a?(Net::HTTPSuccess)
    JSON.parse(response.body)
  end

  def self.fetch_identity(access_token)
    uri = URI("#{BASE_AUTH_URL}/authorization.json")
    request = Net::HTTP::Get.new(uri)
    request["Authorization"] = "Bearer #{access_token}"
    request["User-Agent"] = user_agent

    response = http_start(uri) { |http| http.request(request) }
    raise AuthError, "Identity fetch failed: #{response.code}" unless response.is_a?(Net::HTTPSuccess)
    JSON.parse(response.body)
  end

  def self.refresh_token(refresh_token)
    uri = URI("#{BASE_AUTH_URL}/authorization/token")
    response = http_post_form(uri, {
      grant_type: "refresh_token",
      type: "refresh",
      client_id: credentials[:client_id],
      client_secret: credentials[:client_secret],
      refresh_token: refresh_token
    })

    raise AuthError, "Token refresh failed: #{response.code}" unless response.is_a?(Net::HTTPSuccess)
    JSON.parse(response.body)
  end

  # Launchpad returns expires_in (typically 1209600 = 14 days). Fall back to 2 weeks.
  def self.expires_at_from_token(data)
    expires_in = data.is_a?(Hash) ? data["expires_in"]&.to_i : nil
    expires_in&.positive? ? expires_in.seconds.from_now : 2.weeks.from_now
  end

  def self.persist_tokens!(user, data)
    attrs = {
      basecamp_access_token: data["access_token"],
      basecamp_token_expires_at: expires_at_from_token(data)
    }
    attrs[:basecamp_refresh_token] = data["refresh_token"] if data["refresh_token"].present?
    user.update!(attrs)
  end

  # Launchpad accounts include product=bc3. Basecamp's own authorization.json
  # omits product and uses href / resource instead (bc3-api authentication.md).
  def self.pick_account(accounts)
    list = Array(accounts).select { |a| a.is_a?(Hash) }
    list.find { |a| a["product"].to_s == "bc3" } ||
      list.find { |a| a["href"].to_s.include?("3.basecampapi.com") } ||
      list.find { |a| a["resource"].to_s.start_with?("urn:bc:account:") } ||
      list.first
  end

  def self.account_id_from(account)
    return nil unless account.is_a?(Hash)
    return account["id"].to_s if account["id"].present?

    href_id = account["href"].to_s[/:\/\/3\.basecampapi\.com\/(\d+)/, 1]
    return href_id if href_id.present?

    account["resource"].to_s[/\Aurn:bc:account:(\d+)\z/, 1]
  end

  def self.credentials
    creds = Rails.application.credentials.basecamp
    return creds if creds.present?

    # Fallback to ENV for development/missing credentials
    {
      client_id: ENV["BASECAMP_CLIENT_ID"],
      client_secret: ENV["BASECAMP_CLIENT_SECRET"]
    }
  end

  def self.configured?
    credentials[:client_id].present?
  end

  def self.user_agent
    "Daybreak (kosta@daybreak.app)"
  end

  # API methods

  def my_assignments
    # GET /my/assignments.json returns { "priorities" => [...], "non_priorities" => [...] } (not a top-level array).
    # Assignment rows use type "todo" and "content" for the title (see bc3-api sections/my_assignments.md).
    raw = get("/my/assignments.json")
    normalize_my_assignments_payload(raw)
  end

  # Full result set, not paginated. Used to stamp local rows completed in Basecamp.
  def completed_assignments
    raw = get("/my/assignments/completed.json")
    case raw
    when Array
      raw.flat_map { |a| expand_assignment_with_todo_children(a) }
    when Hash
      normalize_my_assignments_payload(raw)
    else
      []
    end
  end

  def projects
    get_paginated("/projects.json")
  end

  def todo(todo_id)
    get("/todos/#{todo_id}.json")
  end

  # Flat routes are canonical (bc3-api). bucket_id is ignored and kept for callers.
  def complete_todo(bucket_id, todo_id = nil)
    id = todo_id.presence || bucket_id
    post("/todos/#{id}/completion.json")
  end

  def uncomplete_todo(bucket_id, todo_id = nil)
    id = todo_id.presence || bucket_id
    delete("/todos/#{id}/completion.json")
  end

  def schedule_entries(schedule_id)
    get_paginated("/schedules/#{schedule_id}/entries.json")
  end

  # List plus locally expanded recurrences that fall in +starts_on+..+ends_on+.
  # The official list is the series, not occurrences; GET .../occurrences/:date.json
  # is one-day-at-a-time, so common frequencies are expanded here.
  def schedule_entries_in_window(schedule_id, starts_on:, ends_on:)
    entries = schedule_entries(schedule_id)
    return [] unless entries.is_a?(Array)

    range = starts_on.to_date..ends_on.to_date
    entries.flat_map { |entry| expand_schedule_entry_for_range(entry, range) }
  end

  def my_profile
    get("/my/profile.json")
  end

  # Binary image for +url_string+ from +my_profile+ ["avatar_url"] (browser cannot send Bearer token).
  def fetch_avatar_binary(url_string)
    validate_basecamp_avatar_url!(url_string)
    ensure_fresh_token!
    uri = URI.parse(url_string)
    fetch_avatar_http(uri, retrying: false)
  end

  # Discovers schedule IDs from the user's projects via the project "dock".
  # Returns [{ project_id:, project_name:, schedule_id: }, ...]
  def schedules
    projects_data = projects
    return [] unless projects_data.is_a?(Array)

    projects_data.flat_map do |project|
      schedule = project["dock"]&.find { |d| d["name"] == "schedule" }
      next [] unless schedule && schedule["enabled"]
      [ {
        project_id: project["id"],
        project_name: project["name"],
        schedule_id: schedule["id"]
      } ]
    end
  end

  def comments(bucket_id, recording_id = nil)
    id = recording_id.presence || bucket_id
    get_paginated("/recordings/#{id}/comments.json")
  end

  def create_comment(bucket_id, recording_id = nil, content: nil)
    id = recording_id.presence || bucket_id
    post("/recordings/#{id}/comments.json", { content: rich_text_html(content) })
  end

  def create_todolist(todoset_id, name:)
    post("/todosets/#{todoset_id}/todolists.json", { name: name })
  end

  def create_todo(todolist_id, content:, **options)
    post("/todolists/#{todolist_id}/todos.json", { content: content, **options })
  end

  private

  def validate_basecamp_avatar_url!(url_string)
    raise ArgumentError, "blank avatar URL" if url_string.blank?

    uri = URI.parse(url_string)
    path = uri.path.to_s.sub(%r{/\z}, "")
    host = uri.host.to_s
    allowed_host = API_HOSTS_WITH_BEARER.include?(host) ||
      host.downcase.end_with?(BASECAMP_AVATAR_STATIC_HOST_SUFFIX)
    unless uri.scheme == "https" && allowed_host && path.match?(%r{/people/.+/avatar\z})
      raise ArgumentError, "unsafe avatar URL"
    end
  end

  # Avatars often 302 to a CDN (S3, CloudFront, etc.); only the API hop uses Bearer auth.
  def fetch_avatar_http(uri, retrying: false, redirect_count: 0)
    raise "Avatar redirect limit exceeded" if redirect_count > 5

    req = Net::HTTP::Get.new(uri)
    req["Authorization"] = "Bearer #{@user.basecamp_access_token}" if API_HOSTS_WITH_BEARER.include?(uri.host)
    req["User-Agent"] = self.class.user_agent

    # Match #request — Net::HTTP.new(uri.host) can mishandle TLS compared to Net::HTTP.start.
    response = http_start(uri) { |http| http.request(req) }
    code = response.code.to_i

    if code >= 200 && code < 300
      body = response.body
      raise "empty avatar body" if body.blank?

      body = body.dup.force_encoding(Encoding::BINARY)
      ct = response["Content-Type"].to_s.split(";").first.strip.presence || "image/jpeg"
      if ct.present? && !ct.downcase.start_with?("image/")
        Rails.logger.warn("Basecamp avatar unexpected Content-Type: #{ct} (bytes=#{body.bytesize})")
      end
      [ body, ct ]
    elsif code == 401
      raise AuthError, "Session expired" if retrying
      unless API_HOSTS_WITH_BEARER.include?(uri.host)
        raise "Avatar fetch failed: 401 on #{uri.host}"
      end

      perform_token_refresh!
      fetch_avatar_http(uri, retrying: true, redirect_count: redirect_count)
    elsif avatar_redirect_code?(code)
      loc = response["location"]
      raise "avatar redirect without Location" if loc.blank?

      next_uri = URI.join(uri.to_s, loc)
      validate_avatar_redirect_uri!(next_uri)
      fetch_avatar_http(next_uri, retrying: retrying, redirect_count: redirect_count + 1)
    else
      raise "Avatar fetch failed: #{response.code}"
    end
  end

  def avatar_redirect_code?(code)
    code >= 300 && code < 400 && code != 304 && code != 305
  end

  # Any https host except obvious SSRF targets (CDN hostnames vary by region).
  def validate_avatar_redirect_uri!(uri)
    unless uri.scheme == "https" && uri.host.present?
      raise ArgumentError, "unsafe avatar redirect"
    end

    if blocked_avatar_redirect_host?(uri.host)
      raise ArgumentError, "unsafe avatar redirect host: #{uri.host}"
    end
  end

  def blocked_avatar_redirect_host?(host)
    h = host.downcase
    return true if %w[localhost].include?(h) || h.end_with?(".local") || h.end_with?(".localhost")
    return true if h.match?(/\A127\.\d+\.\d+\.\d+\z/) || h.match?(/\A0\.\d+\.\d+\.\d+\z/)

    false
  end

  def get(path, params = {})
    request(:get, path, params)
  end

  # Follows Basecamp's Link: <url>; rel="next" pagination, accumulating all pages into one array.
  def get_paginated(path, params = {})
    ensure_fresh_token!

    account_id = @user.basecamp_account_id
    uri = URI("#{BASE_API_URL}/#{account_id}#{path}")
    uri.query = params.to_query if params.present?

    results = []
    loop do
      req = Net::HTTP::Get.new(uri)
      apply_api_headers!(req)

      response = http_start(uri) { |http| http.request(req) }

      case response
      when Net::HTTPSuccess
        page = JSON.parse(response.body) if response.body.present?
        results.concat(Array(page))
        next_uri = safe_next_page_uri(parse_next_link(response["Link"]))
        break unless next_uri
        uri = next_uri
      when Net::HTTPTooManyRequests
        retry_after = response["Retry-After"]&.to_i || 10
        raise RateLimitError, "Rate limited. Retry after #{retry_after}s"
      when Net::HTTPUnauthorized
        perform_token_refresh!
        apply_api_headers!(req)
        response = http_start(uri) { |http| http.request(req) }
        raise AuthError, "Session expired. Please sign in again." unless response.is_a?(Net::HTTPSuccess)
        page = JSON.parse(response.body) if response.body.present?
        results.concat(Array(page))
        next_uri = safe_next_page_uri(parse_next_link(response["Link"]))
        break unless next_uri
        uri = next_uri
      else
        raise "Basecamp API error: #{response.code} #{response.body}"
      end
    end

    results
  end

  def parse_next_link(link_header)
    return nil if link_header.blank?
    # Link: <https://...?page=2>; rel="next", <https://...?page=5>; rel="last"
    link_header.split(",").each do |part|
      url = part[/<([^>]+)>/, 1]
      next if url.blank?

      rel = part[/\brel\s*=\s*["']?([^"',\s]+)/i, 1]
      return url if rel.to_s.downcase == "next"
    end
    nil
  end

  def safe_next_page_uri(url)
    return nil if url.blank?

    uri = URI(url)
    return nil unless uri.scheme == "https"
    return nil unless uri.host.to_s.downcase == "3.basecampapi.com"

    prefix = "/#{@user.basecamp_account_id}"
    return nil unless uri.path.to_s.start_with?(prefix)

    uri
  rescue URI::InvalidURIError
    nil
  end

  def apply_api_headers!(req)
    req["Authorization"] = "Bearer #{@user.basecamp_access_token}"
    req["User-Agent"] = self.class.user_agent
    req["Accept"] = "application/json"
  end

  # bc3-api rich_text.md: comment content is HTML. Encode entities and turn
  # newlines into <br>. Already-tagged strings (e.g. from Trix) pass through.
  def rich_text_html(content)
    str = content.to_s
    return str if str.include?("<")

    escaped = ERB::Util.html_escape(str)
    "<div>#{escaped.gsub("\n", "<br>")}</div>"
  end

  def post(path, body = nil)
    request(:post, path, body)
  end

  def delete(path)
    request(:delete, path)
  end

  def request(method, path, body_or_params = nil)
    ensure_fresh_token!

    account_id = @user.basecamp_account_id
    uri = URI("#{BASE_API_URL}/#{account_id}#{path}")

    case method
    when :get
      uri.query = body_or_params.to_query if body_or_params.present?
      req = Net::HTTP::Get.new(uri)
    when :post
      req = Net::HTTP::Post.new(uri)
      req.body = body_or_params.to_json if body_or_params
      req["Content-Type"] = "application/json"
    when :delete
      req = Net::HTTP::Delete.new(uri)
    end

    apply_api_headers!(req)

    response = http_start(uri) { |http| http.request(req) }

    case response
    when Net::HTTPSuccess
      JSON.parse(response.body) if response.body.present?
    when Net::HTTPTooManyRequests
      retry_after = response["Retry-After"]&.to_i || 10
      raise RateLimitError, "Rate limited. Retry after #{retry_after}s"
    when Net::HTTPUnauthorized
      refresh_and_retry!(method, path, body_or_params)
    else
      raise "Basecamp API error: #{response.code} #{response.body}"
    end
  end

  def ensure_fresh_token!
    return if @user.basecamp_token_fresh?
    perform_token_refresh!
  end

  def perform_token_refresh!
    # Use with_lock to prevent concurrent refresh races under concurrent job syncs.
    @user.with_lock do
      return if @user.reload.basecamp_token_fresh?

      data = self.class.refresh_token(@user.basecamp_refresh_token)
      self.class.persist_tokens!(@user, data)
    end
  end

  def refresh_and_retry!(method, path, body_or_params)
    perform_token_refresh!
    request(method, path, body_or_params)
  rescue AuthError
    raise AuthError, "Session expired. Please sign in again."
  end

  def identity_id
    @identity_id ||= Rails.cache.fetch("basecamp:identity:#{@user.id}", expires_in: 1.hour) do
      identity = self.class.fetch_identity(@user.basecamp_access_token)
      identity["identity"]["id"]
    end
  end

  def normalize_my_assignments_payload(raw)
    top_level =
      case raw
      when Hash
        Array(raw["priorities"]) + Array(raw["non_priorities"])
      when Array
        raw
      else
        []
      end
    top_level.flat_map { |a| expand_assignment_with_todo_children(a) }
  end

  def expand_assignment_with_todo_children(assignment)
    return [] unless assignment.is_a?(Hash)

    out = [ assignment ]
    Array(assignment["children"]).each do |child|
      next unless child.is_a?(Hash)
      next unless child["type"].to_s.casecmp?("todo")

      out.concat(expand_assignment_with_todo_children(child))
    end
    out
  end

  def expand_schedule_entry_for_range(entry, range)
    return [] unless entry.is_a?(Hash)

    rec = entry["recurrence_schedule"]
    return [ entry ] unless rec.is_a?(Hash) && rec["frequency"].present?

    origin_start = parse_bc_time(entry["starts_at"])
    return [ entry ] unless origin_start

    origin_end = parse_bc_time(entry["ends_at"]) || origin_start
    duration = origin_end - origin_start
    origin_date = civil_date_from_timestamp(entry["starts_at"], origin_start)

    occurrence_dates_in_range(rec, origin_date, range).map do |date|
      new_start = origin_start + (date - origin_date).days
      entry.merge(
        "id" => "#{entry["id"]}:#{date.iso8601}",
        "starts_at" => new_start.iso8601(3),
        "ends_at" => (new_start + duration).iso8601(3)
      )
    end
  end

  def occurrence_dates_in_range(rec, origin_date, range)
    start_date = parse_bc_date(rec["start_date"]) || origin_date
    end_date = parse_bc_date(rec["end_date"])
    first = [ range.begin, start_date ].max
    last = end_date ? [ range.end, end_date ].min : range.end
    return [] if first > last

    (first..last).select { |date| occurrence_on?(rec, origin_date, date, start_date) }
  end

  def occurrence_on?(rec, origin_date, date, start_date)
    return false if date < start_date

    freq = rec["frequency"].to_s
    case freq
    when "every_day"
      days = Array(rec["days"])
      days.empty? || days.map(&:to_i).include?(date.wday)
    when "every_weekday"
      (1..5).include?(date.wday)
    when "every_week"
      date.wday == origin_date.wday
    when "every_other_week"
      date.wday == origin_date.wday && (((date - origin_date).to_i / 7) % 2).zero?
    when "every_day_of_month"
      date.day == origin_date.day
    when "every_year"
      date.month == origin_date.month && date.day == origin_date.day
    when "custom_week"
      interval = rec["week_interval"].to_i
      interval = 2 if interval < 2
      date.wday == origin_date.wday && (((date - origin_date).to_i / 7) % interval).zero?
    when "every_month"
      nth_weekday_of_month?(date, rec, origin_date)
    when "custom_month"
      interval = rec["month_interval"].to_i
      interval = 2 if interval < 2
      months = (date.year * 12 + date.month) - (origin_date.year * 12 + origin_date.month)
      return false unless months >= 0 && (months % interval).zero?

      if rec["week_instance"].present?
        nth_weekday_of_month?(date, rec, origin_date)
      else
        target = Array(rec["days"]).first&.to_i || origin_date.day
        date.day == target
      end
    else
      date == origin_date
    end
  end

  def nth_weekday_of_month?(date, rec, origin_date)
    return false unless date.wday == origin_date.wday

    instance = rec["week_instance"].to_i
    if instance == -1
      (date + 7).month != date.month
    else
      ((date.day - 1) / 7) + 1 == instance
    end
  end

  def parse_bc_time(value)
    return nil if value.blank?

    Time.iso8601(value.to_s)
  rescue ArgumentError, TypeError
    begin
      Time.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end
  end

  def parse_bc_date(value)
    return nil if value.blank?
    Date.iso8601(value.to_s)
  rescue ArgumentError
    nil
  end

  def civil_date_from_timestamp(raw, parsed)
    str = raw.to_s
    return Date.iso8601(str[0, 10]) if str.match?(/\A\d{4}-\d{2}-\d{2}/)

    parsed.to_date
  rescue ArgumentError
    parsed.to_date
  end
end
