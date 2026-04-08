class TriageController < ApplicationController
  def show
    unless current_user.hey_connected?
      redirect_to root_path, alert: "Connect HEY first from Settings." and return
    end

    # Fire-and-forget on-demand refresh so the view always reflects recent state.
    SyncHeyEmailsJob.perform_later(current_user.id)

    @emails_by_folder = current_user.hey_emails
      .for_triage
      .group_by(&:folder)
  end
end
