class SyncCalendarEventsJob < ApplicationJob
  queue_as :sync

  def perform(user_id, week_start: nil)
    user = User.find_by(id: user_id)
    return if user.nil?

    ws = parse_week_start(user, week_start)
    we = ws + 6.days

    basecamp_ok = user.basecamp_access_token.present? ? sync_basecamp(user, ws, we) : true
    hey_ok = user.hey_connected? ? sync_hey(user, ws, we) : true

    # Only broadcast when the week is internally consistent. If either leg failed,
    # the next sync will broadcast once data is clean — prevents flashing partial state.
    broadcast_week_timelines(user, ws) if basecamp_ok && hey_ok
  end

  private

  def parse_week_start(user, value)
    return user.current_week_start if value.blank?

    Date.iso8601(value.to_s)
  rescue ArgumentError
    user.current_week_start
  end

  def broadcast_week_timelines(user, week_start)
    0.upto(6) do |offset|
      TimelineBroadcaster.replace_for_day!(user, week_start + offset.days)
    end
  end

  def sync_basecamp(user, week_start, week_end)
    client = BasecampClient.new(user)
    seen_ids = []
    client.schedules.each do |schedule|
      entries = client.schedule_entries_in_window(
        schedule[:schedule_id],
        starts_on: week_start,
        ends_on: week_end
      )
      next unless entries.is_a?(Array)

      entries.each do |entry|
        ext = upsert_basecamp(user, entry, week_start, week_end)
        seen_ids << ext if ext.present?
      end
    end
    prune_stale_calendar_events!(user, :basecamp, week_start, week_end, seen_ids)
    true
  rescue BasecampClient::AuthError => e
    Rails.logger.warn("Basecamp calendar sync failed for user #{user.id}: #{e.message}")
    false
  rescue BasecampClient::RateLimitError
    self.class.set(wait: 15.seconds).perform_later(user.id, week_start: week_start.iso8601)
    false
  end

  def upsert_basecamp(user, entry, week_start, week_end)
    return unless entry["starts_at"]
    starts_at = Time.parse(entry["starts_at"])
    return unless starts_at.between?(week_start.beginning_of_day, week_end.end_of_day)

    ext = entry["id"].to_s
    event = user.calendar_events.find_or_initialize_by(
      external_id: ext,
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
    ext
  end

  def sync_hey(user, week_start, week_end)
    client = HeyClient.new(user)
    events = []
    week_rows = nil
    recordings = nil

    if client.respond_to?(:calendar_week_events)
      week_rows = client.calendar_week_events(week_start.iso8601)
      events.concat(week_rows) if week_rows.is_a?(Array)
    end

    recordings = client.calendar_events(starts_on: week_start.iso8601, ends_on: week_end.iso8601)
    events.concat(recordings) if recordings.is_a?(Array)

    seen_ids = []
    dedupe_hey_recordings(events).each do |evt|
      ext = upsert_hey(user, evt)
      seen_ids << ext if ext.present?
    end
    reconcile_duplicate_hey_calendar_rows!(user)

    week_ok = !client.respond_to?(:calendar_week_events) || week_rows.is_a?(Array)
    fetch_ok = week_ok && recordings.is_a?(Array)
    rec_complete = !client.respond_to?(:recordings_complete?) || client.recordings_complete?
    if fetch_ok && rec_complete
      prune_stale_calendar_events!(user, :hey, week_start, week_end, seen_ids)
    end
    true
  rescue HeyClient::AuthError => e
    Rails.logger.warn("HEY calendar sync failed for user #{user.id}: #{e.message}")
    false
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
    attrs[:color] = evt["calendar_color"].to_s if evt["calendar_color"].present?
    attrs[:description] = (evt["description"] || evt["notes"]).presence
    attrs[:location] = evt["location"].presence
    attrs[:hey_event_url] = (evt["url"] || evt["join_link"] || evt["link"]).presence
    entry = evt["entry_id"] || evt.dig("attached_entry", "id")
    attrs[:hey_entry_id] = entry.present? ? entry.to_s : nil
    event.update!(attrs)
    ext
  end

  def prune_stale_calendar_events!(user, source, week_start, week_end, current_ids)
    return if source.to_s == "daybreak"

    window = week_start.beginning_of_day..week_end.end_of_day
    scope = user.calendar_events.where(source: source, starts_at: window)
    if current_ids.empty?
      scope.delete_all
    else
      scope.where.not(external_id: current_ids).delete_all
    end
  end
end
