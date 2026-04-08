class HeyEmailsController < ApplicationController
  before_action :set_email

  def triage
    week_start = Date.current.in_time_zone(current_user.timezone).beginning_of_week(:monday)

    ActiveRecord::Base.transaction do
      current_user.task_assignments.create!(
        source: :local,
        title: @email.subject,
        week_start_date: week_start,
        week_bucket: "sometime",
        size: :medium,
        status: :pending
      )
      @email.triage!
    end

    respond_removed("Added to this week.")
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound => e
    Rails.logger.warn("Triage action failed: #{e.message}")
    render json: { error: "Could not save. Try again?" }, status: :unprocessable_entity
  end

  def dismiss
    @email.dismiss!
    respond_removed("Dismissed.")
  end

  private

  def set_email
    @email = current_user.hey_emails.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    # Sync race: the row was pruned between render and click. The row is gone
    # from the DB, so sweep it out of the UI too — don't leave a ghost button.
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.remove("hey_email_#{params[:id]}") }
      format.html { redirect_to triage_path, notice: "Already handled." }
    end
  end

  def respond_removed(notice)
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.remove("hey_email_#{@email.id}") }
      format.html { redirect_to triage_path, notice: notice }
    end
  end
end
