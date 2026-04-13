class JournalController < ApplicationController
  # JSON for the journal-editor HEY pill: refreshes after background SyncJournalJob completes.
  def hey_badge_status
    return head :not_found unless current_user.hey_connected?

    date = Date.parse(params[:date])
    entry = current_user.local_journal_entries.find_by(date: date)
    synced = entry.present? &&
      entry.last_pushed_to_hey_digest.present? &&
      entry.last_pushed_to_hey_digest == entry.content_digest

    state = if entry.blank?
      "idle"
    elsif synced
      "synced"
    else
      "pending"
    end

    render json: { state: state }
  rescue ArgumentError
    head :bad_request
  end

  def upsert
    date = Date.parse(params[:date])
    content = params[:content].to_s

    entry = current_user.local_journal_entries.find_or_initialize_by(date: date)
    entry.content = content

    if content.blank?
      entry.destroy if entry.persisted?
      head :no_content
    elsif entry.save
      if current_user.hey_connected?
        Rails.cache.write("journal_local_push:#{current_user.id}:#{date}", "1", expires_in: 12.seconds)
        SyncJournalJob.perform_later(current_user.id, date.to_s)
      end
      head :no_content
    else
      head :unprocessable_entity
    end
  rescue ArgumentError
    head :bad_request
  end
end
