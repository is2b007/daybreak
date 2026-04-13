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
    if events.is_a?(Array)
      dedupe_hey_recordings(events).each { |evt| upsert_hey(user, evt) }
    end
    reconcile_duplicate_hey_calendar_rows!(user)
  rescue HeyClient::AuthError => e
    Rails.logger.warn("HEY calendar sync failed for user #{user.id}: #{e.message}")
  end

  # HEY sometimes returns the same wall-time recording from multiple calendars with different ids.
  # Collapse to one row per (title, range, all_day) so chips/timeline are not spammed.
  def dedupe_hey_recordings(events)
    events.group_by { |e| hey_recording_fingerprint(e) }.values.map do |group|
      group.min_by { |e| [ e["hey_calendar_id"].to_s, normalize_hey_external_id(e).to_s ] }
    end
  end

  def hey_recording_fingerprint(evt)
    s = (evt["starts_at"] || evt["startsAt"]).to_s
    en = (evt["ends_at"] || evt["endsAt"]).to_s
    ad = (evt["all_day"] || evt["allDay"]).to_s
    t = (evt["title"] || evt["summary"] || evt["name"]).to_s.strip.downcase
    [ s, en, ad, t ]
  end

  def normalize_hey_external_id(evt)
    raw = (evt["id"] || evt["recording_id"]).to_s.strip
    return nil if raw.blank?

    raw =~ %r{/(\d+)\z} ? ::Regexp.last_match(1) : raw
  end

  # Removes extra DB rows left from older syncs before in-batch dedupe (same HEY slot, different ids).
  def reconcile_duplicate_hey_calendar_rows!(user)
    rows = user.calendar_events.where(source: :hey).order(:id).to_a
    rows.group_by { |e| hey_calendar_row_fingerprint(e) }.each_value do |group|
      next if group.size < 2

      keep = group.max_by { |e| e.show_on_week_board? ? 1 : 0 }
      group.reject { |e| e.id == keep.id }.each(&:destroy!)
    end
  end

  def hey_calendar_row_fingerprint(e)
    en = e.ends_at || e.starts_at
    [ e.title.to_s.strip.downcase, e.starts_at.utc.iso8601, en.utc.iso8601, e.all_day ]
  end

  def upsert_hey(user, evt)
    ext = normalize_hey_external_id(evt)
    return if ext.blank?

    starts = evt["starts_at"] || evt["startsAt"]
    return if starts.blank?

    starts_at = Time.parse(starts.to_s)
    ends_raw = evt["ends_at"] || evt["endsAt"]
    all_day_raw = evt["all_day"] || evt["allDay"]
    all_day = ActiveModel::Type::Boolean.new.cast(all_day_raw) == true

    event = user.calendar_events.find_or_initialize_by(
      external_id: ext,
      source: :hey
    )
    completed_raw = evt["completed_at"] || evt["completedAt"]

    attrs = {
      title: evt["title"] || evt["summary"] || evt["name"] || "(untitled)",
      starts_at: starts_at,
      ends_at: ends_raw.present? ? Time.parse(ends_raw.to_s) : nil,
      all_day: all_day,
      completed_at: completed_raw.present? ? Time.zone.parse(completed_raw.to_s) : nil
    }
    attrs[:hey_calendar_id] = evt["hey_calendar_id"].to_s if evt["hey_calendar_id"].present?
    event.update!(attrs)
  end
end
