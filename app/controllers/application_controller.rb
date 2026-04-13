class ApplicationController < ActionController::Base
  include Authentication

  allow_browser versions: :modern
  stale_when_importmap_changes

  before_action :authenticate_user!
  before_action :require_onboarding!
  before_action :load_active_timer
  before_action :load_right_panel_data

  private

  def load_active_timer
    return unless logged_in? && current_user&.onboarded?

    @active_timer = current_user.local_timer_sessions.running.first
  end

  def load_right_panel_data
    return if controller_name == "rituals" && action_name == "evening"
    return unless logged_in? && current_user&.onboarded?

    week_start = Date.current.beginning_of_week(:monday)
    bc_scope = current_user.task_assignments.basecamp.incomplete.where(week_bucket: "inbox").ordered.limit(20)
    @rp_bc_tasks = bc_scope
    @rp_bc_project_names = bc_scope.filter_map { |t| t.project_name&.strip }.uniq.sort
    @rp_bc_has_blank_project = bc_scope.any? { |t| t.project_name.blank? }
    hey_scope = current_user.hey_emails.active
    hey_emails = hey_scope.for_folder(:imbox).ordered.limit(25)
    @rp_hey_emails = hey_emails
    @rp_hey_labels = hey_scope.filter_map(&:label).uniq.compact.sort
    @rp_goals = current_user.weekly_goals.where(week_start_date: week_start)
    @rp_journal = current_user.local_journal_entries.find_by(date: Date.current)
    @rp_journal_hey_synced = @rp_journal.present? &&
      @rp_journal.last_pushed_to_hey_digest.present? &&
      @rp_journal.last_pushed_to_hey_digest == @rp_journal.content_digest
  rescue => e
    Rails.logger.warn "Right panel data load failed: #{e.message}"
    @rp_bc_tasks = []
    @rp_bc_project_names = []
    @rp_bc_has_blank_project = false
    @rp_hey_emails = []
    @rp_hey_labels = []
    @rp_goals = []
    @rp_journal = nil
    @rp_journal_hey_synced = false
  end
end
