class SyncTimeboxToHeyJob < ApplicationJob
  queue_as :default

  def perform(task_assignment_id)
    task = TaskAssignment.find(task_assignment_id)
    return unless task.user.hey_connected? && task.timeboxed?

    user = task.user
    client = HeyClient.new(user)

    CalendarEvent.destroy_daybreak_timebox_mirror!(user, task.id)

    prev_id = task.hey_calendar_event_id
    client.delete_timebox_mirror_remote_id(prev_id) if prev_id.present?

    cal_id = client.calendar_id_for_timed_writes
    tz_name = user.timezone.presence || "UTC"
    zone = ActiveSupport::TimeZone[tz_name] || Time.zone
    local_start = task.planned_start_at.in_time_zone(zone)
    duration = task.planned_duration_minutes.to_i
    duration = 60 if duration <= 0
    local_end = local_start + duration.minutes

    new_id = nil
    if cal_id.present?
      new_id = client.create_timed_calendar_event_form(
        calendar_id: cal_id,
        title: task.title,
        local_start: local_start,
        local_end: local_end,
        time_zone: tz_name
      )
    end

    d = task.planned_start_at.in_time_zone(user.timezone).to_date

    if new_id.present?
      task.update!(hey_calendar_event_id: new_id)
    else
      upsert_daybreak_timebox_mirror!(user, task, local_start, local_end)
      task.update_column(:hey_calendar_event_id, nil)
    end

    TimelineBroadcaster.replace_for_day!(user, d)
  rescue HeyClient::AuthError => e
    Rails.logger.warn("HEY timebox sync failed for task #{task_assignment_id}: #{e.message}")
  end

  private

  def upsert_daybreak_timebox_mirror!(user, task, local_start, local_end)
    ev = user.calendar_events.find_or_initialize_by(
      external_id: CalendarEvent.daybreak_timebox_external_id(task.id),
      source: :daybreak
    )
    ev.update!(
      title: task.title,
      starts_at: local_start,
      ends_at: local_end,
      all_day: false
    )
  end
end
