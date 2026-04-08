class TriageController < ApplicationController
  def show
    unless current_user.hey_connected?
      redirect_to root_path, alert: "Connect HEY first from Settings." and return
    end

    # Fire-and-forget on-demand refresh, but debounce to avoid queue spam.
    # Only sync if we haven't synced in the last 90 seconds.
    last_sync_at = current_user.hey_emails.order(updated_at: :desc).limit(1).pick(:updated_at)
    should_sync = last_sync_at.nil? || (Time.current - last_sync_at) > 90.seconds

    SyncHeyEmailsJob.perform_later(current_user.id) if should_sync

    @emails_by_folder = current_user.hey_emails
      .for_triage
      .group_by(&:folder)
  end
end
