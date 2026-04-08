class SyncCalendarEventsJob < ApplicationJob
  queue_as :sync

  def perform(user_id)
    user = User.find(user_id)
    week_start = Date.current.beginning_of_week(:monday)
    week_end = week_start + 6.days

    sync_basecamp(user, week_start, week_end)
    sync_hey(user, week_start, week_end) if user.hey_connected?
  end

  private

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
    self.class.set(wait: 15.seconds).perform_later(user.id)
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
    return unless evt["starts_at"]

    event = user.calendar_events.find_or_initialize_by(
      external_id: evt["id"].to_s,
      source: :hey
    )
    event.update!(
      title: evt["title"] || evt["summary"] || "(untitled)",
      starts_at: Time.parse(evt["starts_at"]),
      ends_at: evt["ends_at"] && Time.parse(evt["ends_at"]),
      all_day: evt["all_day"] == true
    )
  end
end
