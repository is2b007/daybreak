require "net/http"
require "json"

class HeyClient
  BASE_AUTH_URL = "https://launchpad.37signals.com"
  BASE_API_URL = "https://hey.com/api/v1"

  class AuthError < StandardError; end

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

    raise AuthError, "HEY token exchange failed: #{response.code}" unless response.is_a?(Net::HTTPSuccess)
    JSON.parse(response.body)
  end

  def self.fetch_identity(access_token)
    uri = URI("#{BASE_AUTH_URL}/authorization.json")
    request = Net::HTTP::Get.new(uri)
    request["Authorization"] = "Bearer #{access_token}"
    request["User-Agent"] = user_agent

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(request) }
    raise AuthError, "HEY identity fetch failed: #{response.code}" unless response.is_a?(Net::HTTPSuccess)
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

  def self.credentials
    creds = Rails.application.credentials.hey
    return creds if creds.present?

    { client_id: ENV["HEY_CLIENT_ID"], client_secret: ENV["HEY_CLIENT_SECRET"] }
  end

  def self.configured?
    credentials[:client_id].present?
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
    get("/calendars/#{calendar_id}/recordings")
  end

  # Returns calendar events from all of the user's calendars within a date window.
  # `starts_on` / `ends_on` should be ISO8601 date strings (e.g. "2026-04-08").
  def calendar_events(starts_on:, ends_on:)
    calendars_data = calendars
    return [] unless calendars_data.is_a?(Array)

    calendars_data.flat_map do |cal|
      query = URI.encode_www_form(starts_on: starts_on, ends_on: ends_on)
      events = get("/calendars/#{cal['id']}/events.json?#{query}")
      events.is_a?(Array) ? events : []
    end
  end

  # Todos

  def todos
    get("/calendar/todos.json")
  end

  def create_todo(title:, starts_at: nil, ends_at: nil)
    post("/calendar/todos.json", {
      title: title,
      starts_at: starts_at&.iso8601,
      ends_at: ends_at&.iso8601
    }.compact)
  end

  def complete_todo(todo_id)
    post("/calendar/todos/#{todo_id}/completions")
  end

  def uncomplete_todo(todo_id)
    delete("/calendar/todos/#{todo_id}/completions")
  end

  # Habits

  def complete_habit(day, habit_id)
    post("/calendar/days/#{day}/habits/#{habit_id}/completions")
  end

  # Time tracking

  def current_time_track
    get("/calendar/ongoing_time_track.json")
  end

  def start_time_track(title: nil)
    post("/calendar/ongoing_time_track.json", { title: title }.compact)
  end

  def stop_time_track(time_track_id)
    put("/calendar/time_tracks/#{time_track_id}", { ends_at: Time.current.iso8601 })
  end

  # Journal

  def journal_entry(day)
    get("/calendar/days/#{day}/journal_entry")
  end

  def write_journal(day, content)
    patch("/calendar/days/#{day}/journal_entry", { content: content })
  end

  # Email triage (read-only)
  #
  # HEY's box endpoints return a BoxShowResponse wrapper:
  #   { id:, kind:, name:, postings: [Posting, ...] }
  # Posting shape (polymorphic by `kind`: "topic" | "bundle" | "entry"):
  #   { id:, kind:, name: (subject), summary: (snippet), app_url:,
  #     observed_at:, created_at:, updated_at:, seen:,
  #     creator: { name:, email_address: } }
  #
  # Paths documented in basecamp/hey-cli API-COVERAGE.md.

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

  # Returns the postings array from a BoxShowResponse, or nil on error.
  # nil is meaningful: it tells the sync job "the fetch failed, don't prune."
  # An actual empty folder in HEY still returns [] here.
  def fetch_box(path)
    data = get(path)
    return nil unless data.is_a?(Hash)
    postings = data["postings"]
    postings.is_a?(Array) ? postings : []
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

    case method
    when :get
      req = Net::HTTP::Get.new(uri)
    when :post
      req = Net::HTTP::Post.new(uri)
    when :put
      req = Net::HTTP::Put.new(uri)
    when :patch
      req = Net::HTTP::Patch.new(uri)
    when :delete
      req = Net::HTTP::Delete.new(uri)
    end

    req["Authorization"] = "Bearer #{@user.hey_access_token}"
    req["Content-Type"] = "application/json"
    req["Accept"] = "application/json"
    req["User-Agent"] = self.class.user_agent

    if body
      req.body = body.to_json
    end

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }

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
end
