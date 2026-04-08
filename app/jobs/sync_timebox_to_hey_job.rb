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

    task.update!(hey_calendar_event_id: result&.dig("id")&.to_s)
  rescue HeyClient::AuthError => e
    Rails.logger.warn("HEY timebox sync failed for task #{task_assignment_id}: #{e.message}")
  end
end
