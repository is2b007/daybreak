class SyncInboxSometimeTodoToHeyJob < ApplicationJob
  queue_as :default

  def perform(task_assignment_id)
    task = TaskAssignment.find_by(id: task_assignment_id)
    return if task.blank?

    user = task.user
    return unless user.hey_connected?
    return unless task.week_bucket == "sometime" && task.hey_app_url.present?
    return if task.hey_mirrored_todo_id.present?

    client = HeyClient.new(user)
    result = client.create_todo(title: task.title)
    new_id = extract_todo_id(result)
    return if new_id.blank?

    task.update_column(:hey_mirrored_todo_id, new_id)
  rescue HeyClient::AuthError => e
    Rails.logger.warn("HEY inbox sometime todo sync failed for task #{task_assignment_id}: #{e.message}")
  end

  private

  def extract_todo_id(data)
    return nil unless data.is_a?(Hash)

    data["id"]&.to_s || data.dig("calendar_todo", "id")&.to_s
  end
end
