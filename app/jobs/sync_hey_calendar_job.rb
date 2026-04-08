class SyncHeyCalendarJob < ApplicationJob
  queue_as :sync

  def perform(user_id)
    user = User.find(user_id)
    return unless user.hey_connected?

    client = HeyClient.new(user)
    week_start = Date.current.beginning_of_week(:monday)

    # Sync HEY todos
    todos = client.todos
    return unless todos.is_a?(Array)

    todos.each do |todo|
      external_id = todo["id"].to_s
      existing = user.task_assignments.find_by(external_id: external_id, source: :hey)

      if existing
        existing.update!(title: todo["title"]) if existing.title != todo["title"]
      else
        user.task_assignments.create!(
          external_id: external_id,
          source: :hey,
          title: todo["title"],
          week_start_date: week_start,
          week_bucket: "sometime",
          size: :medium,
          status: todo["completed"] ? :completed : :pending
        )
      end
    end
  rescue HeyClient::AuthError => e
    Rails.logger.warn("HEY auth failed for user #{user_id}: #{e.message}")
  end
end
