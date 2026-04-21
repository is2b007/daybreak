class SyncBasecampAssignmentsJob < ApplicationJob
  queue_as :sync

  def perform(user_id, basecamp_client_class: BasecampClient)
    user = User.find(user_id)
    client = basecamp_client_class.new(user)

    assignments = client.my_assignments
    if assignments.is_a?(Array)
      assignments.each do |assignment|
        next unless assignment["type"].to_s.casecmp?("todo")

        title = assignment["title"].presence || assignment["content"].presence || "(untitled)"
        external_id = assignment["id"].to_s
        existing = user.task_assignments.find_by(external_id: external_id, source: :basecamp)

        if existing
          # Update title if changed, but don't overwrite local changes
          existing.update!(title: title) if existing.title != title
        else
          user.task_assignments.create!(
            external_id: external_id,
            source: :basecamp,
            title: title,
            description: assignment["description"],
            project_name: assignment.dig("bucket", "name"),
            basecamp_bucket_id: assignment.dig("bucket", "id")&.to_s,
            week_bucket: "inbox",
            size: :medium,
            status: assignment["completed"] ? :completed : :pending
          )
        end
      end
    end

    user.sync_basecamp_avatar_url_from_api!
  rescue BasecampClient::AuthError => e
    Rails.logger.warn("Basecamp auth failed for user #{user_id}: #{e.message}")
  rescue BasecampClient::RateLimitError
    self.class.set(wait: 15.seconds).perform_later(user_id)
  rescue StandardError => e
    Rails.logger.error("SyncBasecampAssignmentsJob failed for user #{user_id}: #{e.class}: #{e.message}")
    raise e
  end
end
