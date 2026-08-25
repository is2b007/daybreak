class SyncBasecampAssignmentsJob < ApplicationJob
  queue_as :sync

  def perform(user_id, basecamp_client_class: BasecampClient)
    user = User.find_by(id: user_id)
    return if user.nil?

    client = basecamp_client_class.new(user)

    assignments = client.my_assignments
    if assignments.is_a?(Array)
      assignments.each { |assignment| upsert_basecamp_assignment(user, assignment) }
    end

    completed = client.respond_to?(:completed_assignments) ? client.completed_assignments : []
    if completed.is_a?(Array)
      completed.each { |assignment| stamp_completed_basecamp_assignment(user, assignment) }
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

  private

  def upsert_basecamp_assignment(user, assignment)
    return unless assignment.is_a?(Hash)
    return unless assignment["type"].to_s.casecmp?("todo")

    title = assignment["title"].presence || assignment["content"].presence || "(untitled)"
    external_id = assignment["id"].to_s
    existing = user.task_assignments.find_by(external_id: external_id, source: :basecamp)

    if existing
      updates = {}
      updates[:title] = title if existing.title != title
      bucket_id = assignment.dig("bucket", "id")&.to_s
      updates[:basecamp_bucket_id] = bucket_id if bucket_id.present? && existing.basecamp_bucket_id.blank?
      project_name = assignment.dig("bucket", "name")
      updates[:project_name] = project_name if project_name.present? && existing.project_name.blank?
      existing.update!(updates) if updates.any?
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

  # GET /my/assignments.json is active-only. Completed todos vanish from that
  # payload; mark matching local rows complete without creating history items.
  def stamp_completed_basecamp_assignment(user, assignment)
    return unless assignment.is_a?(Hash)
    return unless assignment["type"].to_s.casecmp?("todo")

    existing = user.task_assignments.find_by(external_id: assignment["id"].to_s, source: :basecamp)
    return if existing.nil? || existing.completed?

    existing.complete!
  end
end
