class SyncCalendarEventsJob < ApplicationJob
  queue_as :sync

  def perform(user_id, week_start: nil)
    user = User.find(user_id)
    ws = parse_week_start(week_start)
    we = ws + 6.days

    sync_basecamp(user, ws, we) if user.basecamp_access_token.present?
    sync_hey(user, ws, we) if user.hey_connected?

    broadcast_week_timelines(user, ws)
  end

  private

  def parse_week_start(value)
    return Date.current.beginning_of_week(:monday) if value.blank?

    Date.iso8601(value.to_s)
  rescue ArgumentError
    Date.current.beginning_of_week(:monday)
  end

  def broadcast_week_timelines(user, week_start)
    0.upto(6) do |offset|
      TimelineBroadcaster.replace_for_day!(user, week_start + offset.days)
    end
  end

  def sync_basecamp(user, week_start, week_end)
    client = BasecampClient.new(user)
    client.schedules.each do |schedule|
      entries = client.schedule_entries(schedule[:schedule_id])
      next unless entries.is_a?(Array)

      entries.each { |entry| upsert_basecamp(user, entry, week_start, week_end) }
    end
  rescue BasecampClient::AuthError => e
    Rails.logger.warn("Basecamp calendar sync failed for user #{user.id}: #{e.message}")
  rescue BasecampClient::RateLimitError => e
    self.class.set(wait: 15.seconds).perform_later(user.id, week_start: week_start.iso8601)
  end

  def upsert_basecamp(user, entry, week_start, week_end)
    return unless entry["starts_at"]
    starts_at = Time.parse(entry["starts_at"])
    return unless starts_at.between?(week_start.beginning_of_day, week_end.end_of_day)

    event = user.calendar_events.find_or_initialize_by(
      external_id: entry["id"].to_s,
      source: :basecamp
    )
    event.update!(
      title: entry["summary"] || entry["title"] || "(untitled)",
      starts_at: starts_at,
      ends_at: entry["ends_at"] && Time.parse(entry["ends_at"]),
      all_day: entry["all_day"] == true,
      description: entry["description"],
      basecamp_bucket_id: entry.dig("bucket", "id")&.to_s
    )
  end

  def sync_hey(user, week_start, week_end)
    client = HeyClient.new(user)
    events = client.calendar_events(starts_on: week_start.iso8601, ends_on: week_end.iso8601)
    return unless events.is_a?(Array)

    events.each { |evt| upsert_hey(user, evt) }
  rescue HeyClient::AuthError => e
    Rails.logger.warn("HEY calendar sync failed for user #{user.id}: #{e.message}")
  end

  def upsert_hey(user, evt)
    starts = evt["starts_at"] || evt["startsAt"]
    return if starts.blank?

    starts_at = Time.parse(starts.to_s)
    ends_raw = evt["ends_at"] || evt["endsAt"]
    all_day_raw = evt["all_day"] || evt["allDay"]
    all_day = [ true, "true", 1 ].include?(all_day_raw)

    event = user.calendar_events.find_or_initialize_by(
      external_id: evt["id"].to_s,
      source: :hey
    )
    attrs = {
      title: evt["title"] || evt["summary"] || evt["name"] || "(untitled)",
      starts_at: starts_at,
      ends_at: ends_raw.present? ? Time.parse(ends_raw.to_s) : nil,
      all_day: all_day
    }
    attrs[:hey_calendar_id] = evt["hey_calendar_id"].to_s if evt["hey_calendar_id"].present?
    event.update!(attrs)
  end
end
