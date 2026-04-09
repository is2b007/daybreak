class SyncController < ApplicationController
  def basecamp
    SyncBasecampAssignmentsJob.perform_now(current_user.id)
    SyncCalendarEventsJob.perform_later(current_user.id)
    redirect_back_or_to root_path, notice: "Basecamp tasks updated."
  rescue StandardError => e
    Rails.logger.error("SyncController#basecamp failed: #{e.class}: #{e.message}")
    redirect_back_or_to root_path, alert: "Could not sync with Basecamp. Try again in a moment."
  end
end
