require "net/http"
require "json"

class BasecampClient
  BASE_AUTH_URL = "https://launchpad.37signals.com"
  BASE_API_URL = "https://3.basecampapi.com"

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

  # API methods

  def my_assignments
    # Fetch todos assigned to the current user across all projects
    get("/people/#{identity_id}/assignments.json")
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

  def create_todolist(todoset_id, name:)
    post("/todosets/#{todoset_id}/todolists.json", { name: name })
  end

  def create_todo(todolist_id, content:, **options)
    post("/todolists/#{todolist_id}/todos.json", { content: content, **options })
  end

  private

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
end
