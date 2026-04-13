class SyncTimeboxToHeyJob < ApplicationJob
  queue_as :default

  def perform(task_assignment_id)
    task = TaskAssignment.find(task_assignment_id)
    return unless task.user.hey_connected? && task.timeboxed?

    client = HeyClient.new(task.user)
    ends_at = task.planned_start_at + (task.planned_duration_minutes || 60).minutes

    result = client.create_todo(
      title: task.title,
      starts_at: task.planned_start_at,
      ends_at: ends_at
    )

    new_id = extract_todo_id(result)
    return if new_id.blank?

    if task.hey_calendar_event_id.present? && task.hey_calendar_event_id != new_id
      client.delete_todo(task.hey_calendar_event_id)
    end

    task.update!(hey_calendar_event_id: new_id)
  rescue HeyClient::AuthError => e
    Rails.logger.warn("HEY timebox sync failed for task #{task_assignment_id}: #{e.message}")
  end

  private

  def extract_todo_id(data)
    return nil unless data.is_a?(Hash)

    data["id"]&.to_s || data.dig("calendar_todo", "id")&.to_s
  end
end
