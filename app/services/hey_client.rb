require "net/http"
require "json"

class HeyClient
  BASE_URL = "https://hey.com/api/v1"

  class AuthError < StandardError; end

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

  private

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
    uri = URI("#{BASE_URL}#{path}")

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

    if body
      req.body = body.to_json
    end

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }

    case response
    when Net::HTTPSuccess
      JSON.parse(response.body) if response.body.present?
    when Net::HTTPUnauthorized
      raise AuthError, "HEY token expired. Reconnect in Settings."
    else
      Rails.logger.error("HEY API error: #{response.code} #{response.body}")
      nil
    end
  end
end
