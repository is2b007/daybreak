class SyncTimeboxToHeyJob < ApplicationJob
  queue_as :default

  def perform(task_assignment_id)
    task = TaskAssignment.find(task_assignment_id)
    return unless task.user.hey_connected? && task.timeboxed?

    user = task.user
    calendar_id = user.hey_default_calendar_id.presence
    if calendar_id.blank?
      Rails.logger.warn("SyncTimeboxToHeyJob: no hey_default_calendar_id for user #{user.id}, skipping")
      return
    end

    client = HeyClient.new(user)
    ends_at = task.planned_start_at + (task.planned_duration_minutes || 60).minutes
    prev_id = task.hey_calendar_event_id

    new_id = if prev_id.present?
      res = client.update_calendar_event(
        calendar_id: calendar_id,
        event_id: prev_id,
        title: task.title,
        starts_at: task.planned_start_at,
        ends_at: ends_at,
        all_day: false
      )
      if !res.nil?
        prev_id
      else
        cleanup_stale_remote_mirror!(client, calendar_id, prev_id)
        extract_event_id(
          client.create_calendar_event(
            calendar_id: calendar_id,
            title: task.title,
            starts_at: task.planned_start_at,
            ends_at: ends_at,
            all_day: false
          )
        )
      end
    else
      extract_event_id(
        client.create_calendar_event(
          calendar_id: calendar_id,
          title: task.title,
          starts_at: task.planned_start_at,
          ends_at: ends_at,
          all_day: false
        )
      )
    end

    return if new_id.blank?

    task.update!(hey_calendar_event_id: new_id)

    d = task.planned_start_at.in_time_zone(user.timezone).to_date
    TimelineBroadcaster.replace_for_day!(user, d)
  rescue HeyClient::AuthError => e
    Rails.logger.warn("HEY timebox sync failed for task #{task_assignment_id}: #{e.message}")
  end

  private

  def cleanup_stale_remote_mirror!(client, calendar_id, stale_id)
    begin
      client.delete_todo(stale_id)
    rescue StandardError
      nil
    end
    begin
      client.delete_calendar_event(calendar_id: calendar_id, event_id: stale_id)
    rescue StandardError
      nil
    end
  end

  def extract_event_id(data)
    return nil unless data.is_a?(Hash)

    data["id"]&.to_s || data.dig("calendar_event", "id")&.to_s
  end
end
