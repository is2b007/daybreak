class SyncHeyCalendarJob < ApplicationJob
  queue_as :sync

  def perform(user_id)
    user = User.find(user_id)
    return unless user.hey_connected?

    client = HeyClient.new(user)
    week_start = user.current_week_start

    # Sync HEY todos
    todos = client.todos
    return unless todos.is_a?(Array)

    todos.each do |todo|
      external_id = todo["id"].to_s
      completed = [ true, "true", 1 ].include?(todo["completed"])
      desired_status = completed ? :completed : :pending

      mirrored = user.task_assignments.find_by(hey_mirrored_todo_id: external_id)
      if mirrored
        attrs = {}
        attrs[:title] = todo["title"] if mirrored.title != todo["title"]
        attrs[:status] = desired_status if mirrored.completed? != completed
        mirrored.update!(attrs) if attrs.any?
        next
      end

      existing = user.task_assignments.find_by(external_id: external_id, source: :hey)
      if existing
        attrs = {}
        attrs[:title] = todo["title"] if existing.title != todo["title"]
        attrs[:status] = desired_status if existing.completed? != completed
        existing.update!(attrs) if attrs.any?
      else
        user.task_assignments.create!(
          external_id: external_id,
          source: :hey,
          title: todo["title"],
          week_start_date: week_start,
          week_bucket: "sometime",
          size: :medium,
          status: desired_status
        )
      end
    end
  rescue HeyClient::AuthError => e
    Rails.logger.warn("HEY auth failed for user #{user_id}: #{e.message}")
  end
end
