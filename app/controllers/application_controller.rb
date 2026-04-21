class ApplicationController < ActionController::Base
  include Authentication
  include WeekBoardDayColumn

  allow_browser versions: :modern
  stale_when_importmap_changes

  before_action :authenticate_user!
  before_action :require_onboarding!
  around_action :set_user_timezone
  before_action :load_active_timer
  before_action :load_right_panel_data

  private

  def set_user_timezone
    tz = logged_in? && current_user&.timezone.present? ? current_user.timezone : "UTC"
    Time.use_zone(tz) { yield }
  end

  def load_active_timer
    return unless logged_in? && current_user&.onboarded?

    @active_timer = current_user.local_timer_sessions.running.first
  end

  def load_right_panel_data
    return if controller_name == "rituals" && action_name == "evening"
    return unless logged_in? && current_user&.onboarded?

    @right_panel_errors = []
    week_start = current_user.current_week_start

    load_right_panel_basecamp
    load_right_panel_hey
    load_right_panel_goals_and_journal(week_start)
  end

  def load_right_panel_basecamp
    bc_scope = current_user.task_assignments.basecamp.incomplete.where(week_bucket: "inbox").ordered.limit(20)
    @rp_bc_tasks = bc_scope
    @rp_bc_project_names = bc_scope.filter_map { |t| t.project_name&.strip }.uniq.sort
    @rp_bc_has_blank_project = bc_scope.any? { |t| t.project_name.blank? }
  rescue => e
    Rails.logger.warn "Right panel (Basecamp) load failed: #{e.class}: #{e.message}"
    @rp_bc_tasks = []
    @rp_bc_project_names = []
    @rp_bc_has_blank_project = false
    @right_panel_errors << "Basecamp tasks didn't load"
  end

  def load_right_panel_hey
    hey_scope = current_user.hey_emails.active
    @rp_hey_emails = hey_scope.for_folder(:imbox).ordered.limit(25)
    @rp_hey_labels = hey_scope.filter_map(&:label).uniq.compact.sort
  rescue => e
    Rails.logger.warn "Right panel (HEY) load failed: #{e.class}: #{e.message}"
    @rp_hey_emails = []
    @rp_hey_labels = []
    @right_panel_errors << "HEY inbox didn't load"
  end

  def load_right_panel_goals_and_journal(week_start)
    @rp_goals = current_user.weekly_goals.where(week_start_date: week_start).order(:position, :id)
    @rp_goal_progress = WeeklyGoal.progress_totals_for_week(current_user, week_start)
    @rp_journal = current_user.local_journal_entries.find_by(date: current_user.today_in_zone)
    @rp_journal_hey_synced = @rp_journal.present? &&
      @rp_journal.last_pushed_to_hey_digest.present? &&
      @rp_journal.last_pushed_to_hey_digest == @rp_journal.content_digest
  rescue => e
    Rails.logger.warn "Right panel (goals/journal) load failed: #{e.class}: #{e.message}"
    @rp_goals = []
    @rp_goal_progress = {}
    @rp_journal = nil
    @rp_journal_hey_synced = false
    @right_panel_errors << "Goals or journal didn't load"
  end
end
