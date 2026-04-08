class SyncJournalJob < ApplicationJob
  queue_as :default

  def perform(user_id, date_string)
    user = User.find(user_id)
    return unless user.hey_connected?

    date = Date.parse(date_string)
    client = HeyClient.new(user)

    # Combine daily log entries and reflection
    daily_log = user.daily_logs.find_by(date: date)
    journal_entry = user.local_journal_entries.find_by(date: date)

    content_parts = []

    if daily_log&.log_entries&.any?
      content_parts << daily_log.formatted_content
    end

    if journal_entry
      content_parts << "\n---\nReflection: #{journal_entry.content}"
    end

    return if content_parts.empty?

    client.write_journal(date.to_s, content_parts.join("\n\n"))
  rescue HeyClient::AuthError => e
    Rails.logger.warn("HEY journal sync failed for user #{user_id}: #{e.message}")
  end
end
