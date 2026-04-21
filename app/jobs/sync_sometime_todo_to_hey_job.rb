class SyncSometimeTodoToHeyJob < ApplicationJob
  queue_as :default

  def perform(task_assignment_id)
    task = TaskAssignment.find_by(id: task_assignment_id)
    return if task.blank?

    user = task.user
    return unless user.hey_connected?
    return unless task.week_bucket == "sometime"
    return if task.hey_mirrored_todo_id.present?

    week_start = task.week_start_date || user.current_week_start
    tz = ActiveSupport::TimeZone[user.timezone] || Time.zone
    anchor = tz.local(week_start.year, week_start.month, week_start.day, 12, 0) + 6.days

    client = HeyClient.new(user)
    result = client.create_todo(title: task.title, starts_at: anchor.to_date.iso8601)
    new_id = extract_todo_id(result)
    return if new_id.blank?

    task.update_column(:hey_mirrored_todo_id, new_id)
  rescue HeyClient::AuthError => e
    Rails.logger.warn("HEY sometime todo sync failed for task #{task_assignment_id}: #{e.message}")
  end

  private

  def extract_todo_id(data)
    return nil unless data.is_a?(Hash)

    data["id"]&.to_s || data.dig("calendar_todo", "id")&.to_s
  end
end
