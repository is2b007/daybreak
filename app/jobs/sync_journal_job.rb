class SyncJournalJob < ApplicationJob
  queue_as :default

  def perform(user_id, date_string)
    user = User.find(user_id)
    return unless user.hey_connected?

    date = Date.parse(date_string)
    client = HeyClient.new(user)

    daily_log = user.daily_logs.find_by(date: date)
    journal_entry = user.local_journal_entries.find_by(date: date)

    scratch = journal_entry&.plain_text_for_hey.to_s.strip
    log_block = if daily_log&.log_entries&.any?
      "---\nDay log\n\n#{daily_log.formatted_content}"
    end

    parts = []
    parts << scratch if scratch.present?
    parts << log_block if log_block.present?

    return if parts.empty?

    body = parts.join("\n\n")
    result = client.write_journal(date.to_s, body)

    if result
      journal_entry&.reload
      if journal_entry
        journal_entry.update_column(:last_pushed_to_hey_digest, journal_entry.content_digest)
      end
    else
      Rails.logger.warn("HEY write_journal returned non-success for user #{user_id} date #{date}")
    end
  rescue HeyClient::AuthError => e
    Rails.logger.warn("HEY journal sync failed for user #{user_id}: #{e.message}")
  end
end
