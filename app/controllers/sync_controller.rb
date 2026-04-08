class SyncController < ApplicationController
  def basecamp
    SyncBasecampAssignmentsJob.perform_later(current_user.id)
    SyncCalendarEventsJob.perform_later(current_user.id)
    redirect_back_or_to root_path, notice: "Syncing with Basecamp…"
  end
end
