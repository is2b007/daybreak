class DeleteHeyMirroredTodoJob < ApplicationJob
  queue_as :default

  def perform(user_id, hey_todo_id)
    return if hey_todo_id.blank?

    user = User.find_by(id: user_id)
    return unless user&.hey_connected?

    HeyClient.new(user).delete_todo(hey_todo_id)
  rescue HeyClient::AuthError => e
    Rails.logger.warn("HEY mirrored todo delete failed: #{e.message}")
  end
end
