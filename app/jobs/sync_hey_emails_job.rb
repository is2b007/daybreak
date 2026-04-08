class SyncHeyEmailsJob < ApplicationJob
  queue_as :sync

  PER_FOLDER_CAP = 25

  FOLDER_FETCHERS = {
    imbox: :imbox,
    reply_later: :reply_later,
    set_aside: :set_aside
  }.freeze

  def perform(user_id)
    user = User.find(user_id)
    return unless user.hey_connected?

    client = HeyClient.new(user)

    FOLDER_FETCHERS.each do |folder, method|
      postings = client.public_send(method)
      next unless postings.is_a?(Array)

      postings = postings.select { |p| triagable?(p) }.first(PER_FOLDER_CAP)

      upsert(user, folder, postings)
      prune_stale(user, folder, postings)
    end
  rescue HeyClient::AuthError => e
    Rails.logger.warn("HEY email sync failed for user #{user_id}: #{e.message}")
  end

  private

  # Only topics and bundles surface at the box level for triage.
  # Individual entries are replies within a thread and shouldn't appear here.
  def triagable?(posting)
    %w[topic bundle].include?(posting["kind"])
  end

  def upsert(user, folder, postings)
    postings.each do |posting|
      row = user.hey_emails.find_or_initialize_by(external_id: posting["id"].to_s)

      # Never touch dismissed_at / triaged_at during sync — those are local state.
      attrs = {
        folder: folder,
        sender_name: posting.dig("creator", "name"),
        sender_email: posting.dig("creator", "email_address"),
        subject: posting["name"].presence || "(no subject)",
        snippet: posting["summary"],
        hey_url: posting["app_url"]
      }

      # parse_time handles bad/missing timestamps gracefully, preserving existing received_at if needed.
      new_time = parse_time(posting["observed_at"] || posting["updated_at"] || posting["created_at"], row)
      attrs[:received_at] = new_time if new_time.present?

      row.assign_attributes(attrs)
      row.save! if row.changed?
    end
  end

  def prune_stale(user, folder, postings)
    current_ids = postings.map { |p| p["id"].to_s }
    scope = user.hey_emails
      .where(folder: folder, dismissed_at: nil, triaged_at: nil)
    # Always apply the exclusion, even if current_ids is empty.
    # This prevents deleting all rows when a fetch returns [].
    scope = scope.where.not(external_id: current_ids)
    scope.delete_all
  end

  def parse_time(value, row = nil)
    return nil if value.blank?
    Time.parse(value.to_s)
  rescue ArgumentError
    # If timestamp is malformed, preserve the row's existing received_at
    # rather than defaulting to Time.current (which corrupts sort order).
    row&.received_at.presence
  end
end
