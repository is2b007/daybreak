class ImportHeyJournalJob < ApplicationJob
  queue_as :sync

  def perform(user_id, date_string)
    user = User.find(user_id)
    return unless user.hey_connected?

    date = Date.parse(date_string)
    data = HeyClient.new(user).journal_entry(date.to_s)
    return if data.nil?

    hey_plain = (data["content"] || data["body"]).to_s.strip
    return if hey_plain.blank?

    local = user.local_journal_entries.find_by(date: date)

    if local
      if local.last_pushed_to_hey_digest.present? && local.content_digest != local.last_pushed_to_hey_digest
        return
      end

      if local.last_pushed_to_hey_digest.blank? && local.plain_text_for_hey.present?
        return
      end

      return if local.plain_text_for_hey.strip == hey_plain
    end

    html = LocalJournalEntry.html_from_plain_text(hey_plain)
    digest = Digest::SHA256.hexdigest(html)

    if local
      local.update!(content: html, last_pushed_to_hey_digest: digest)
    else
      user.local_journal_entries.create!(date: date, content: html, last_pushed_to_hey_digest: digest)
    end
  rescue HeyClient::AuthError => e
    Rails.logger.warn("HEY journal import failed for user #{user_id}: #{e.message}")
  end
end
