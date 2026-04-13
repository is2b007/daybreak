class JournalController < ApplicationController
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
