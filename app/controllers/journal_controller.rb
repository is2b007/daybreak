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
      head :no_content
    else
      head :unprocessable_entity
    end
  rescue ArgumentError
    head :bad_request
  end
end
