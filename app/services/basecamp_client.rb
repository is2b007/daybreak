require "net/http"
require "json"

class BasecampClient
  BASE_AUTH_URL = "https://launchpad.37signals.com"
  BASE_API_URL = "https://3.basecampapi.com"
  # Avatar GET may 302 to arbitrary CDNs; Bearer auth is only for these API hosts.
  API_HOSTS_WITH_BEARER = %w[3.basecampapi.com 3.basecamp.com].freeze

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
    response = Net::HTTP.post_form(uri, {
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

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(request) }
    raise AuthError, "Identity fetch failed: #{response.code}" unless response.is_a?(Net::HTTPSuccess)
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

    raise AuthError, "Token refresh failed: #{response.code}" unless response.is_a?(Net::HTTPSuccess)
    JSON.parse(response.body)
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
    # BC3: GET /my/assignments.json returns { "priorities" => [...], "non_priorities" => [...] } (not a top-level array).
    # Assignment rows use type "todo" and "content" for the title (see bc3-api sections/my_assignments.md).
    raw = get("/my/assignments.json")
    normalize_my_assignments_payload(raw)
  end

  def projects
    get("/projects.json")
  end

  def todo(todo_id)
    get("/todos/#{todo_id}.json")
  end

  def complete_todo(bucket_id, todo_id)
    post("/buckets/#{bucket_id}/todos/#{todo_id}/completion.json")
  end

  def uncomplete_todo(bucket_id, todo_id)
    delete("/buckets/#{bucket_id}/todos/#{todo_id}/completion.json")
  end

  def schedule_entries(schedule_id)
    get("/schedules/#{schedule_id}/entries.json")
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

  def comments(bucket_id, recording_id)
    get("/buckets/#{bucket_id}/recordings/#{recording_id}/comments.json")
  end

  def create_comment(bucket_id, recording_id, content:)
    post("/buckets/#{bucket_id}/recordings/#{recording_id}/comments.json",
         { content: content })
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
    unless uri.scheme == "https" && API_HOSTS_WITH_BEARER.include?(uri.host) && path.match?(%r{/people/.+/avatar\z})
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
    response = Net::HTTP.start(
      uri.hostname,
      uri.port,
      use_ssl: uri.scheme == "https",
      open_timeout: 10,
      read_timeout: 30
    ) { |http| http.request(req) }
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

    req["Authorization"] = "Bearer #{@user.basecamp_access_token}"
    req["User-Agent"] = self.class.user_agent

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }

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
    data = self.class.refresh_token(@user.basecamp_refresh_token)
    @user.update!(
      basecamp_access_token: data["access_token"],
      basecamp_token_expires_at: 2.weeks.from_now
    )
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
end
