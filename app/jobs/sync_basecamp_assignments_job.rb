class SyncBasecampAssignmentsJob < ApplicationJob
  queue_as :sync

  def perform(user_id)
    user = User.find(user_id)
    client = BasecampClient.new(user)
    week_start = Date.current.beginning_of_week(:monday)

    assignments = client.my_assignments
    return unless assignments.is_a?(Array)

    assignments.each do |assignment|
      next unless assignment["type"] == "Todo"

      external_id = assignment["id"].to_s
      existing = user.task_assignments.find_by(external_id: external_id, source: :basecamp)

      if existing
        # Update title if changed, but don't overwrite local changes
        existing.update!(title: assignment["title"]) if existing.title != assignment["title"]
      else
        user.task_assignments.create!(
          external_id: external_id,
          source: :basecamp,
          title: assignment["title"],
          description: assignment["description"],
          project_name: assignment.dig("bucket", "name"),
          basecamp_bucket_id: assignment.dig("bucket", "id")&.to_s,
          week_start_date: week_start,
          week_bucket: "sometime",
          size: :medium,
          status: assignment["completed"] ? :completed : :pending
        )
      end
    end
  rescue BasecampClient::AuthError => e
    Rails.logger.warn("Basecamp auth failed for user #{user_id}: #{e.message}")
  rescue BasecampClient::RateLimitError => e
    # Retry after delay
    self.class.set(wait: 15.seconds).perform_later(user_id)
  end
end
