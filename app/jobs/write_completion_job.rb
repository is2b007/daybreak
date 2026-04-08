class WriteCompletionJob < ApplicationJob
  queue_as :default

  def perform(task_assignment_id)
    task = TaskAssignment.find(task_assignment_id)
    user = task.user
    return unless task.completed?

    case task.source
    when "basecamp"
      client = BasecampClient.new(user)
      client.complete_todo(task.basecamp_bucket_id, task.external_id)
    when "hey"
      return unless user.hey_connected?
      client = HeyClient.new(user)
      client.complete_todo(task.external_id)
    end
  rescue => e
    Rails.logger.error("Failed to write completion for task #{task_assignment_id}: #{e.message}")
  end
end
