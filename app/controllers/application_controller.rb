class ApplicationController < ActionController::Base
  include Authentication

  allow_browser versions: :modern
  stale_when_importmap_changes

  before_action :authenticate_user!
  before_action :require_onboarding!
  before_action :load_right_panel_data

  private

  def load_right_panel_data
    return unless logged_in? && current_user&.onboarded?

    week_start = Date.current.beginning_of_week(:monday)
    bc_scope = current_user.task_assignments.basecamp.incomplete.where(week_bucket: "inbox").ordered.limit(20)
    @rp_bc_tasks = bc_scope
    @rp_bc_project_names = bc_scope.filter_map { |t| t.project_name&.strip }.uniq.sort
    @rp_bc_has_blank_project = bc_scope.any? { |t| t.project_name.blank? }
    @rp_hey_tasks = current_user.task_assignments.hey.incomplete.where(week_bucket: "inbox").ordered.limit(20)
    @rp_goals = current_user.weekly_goals.where(week_start_date: week_start)
  rescue => e
    Rails.logger.warn "Right panel data load failed: #{e.message}"
    @rp_bc_tasks = []
    @rp_bc_project_names = []
    @rp_bc_has_blank_project = false
    @rp_hey_tasks = []
    @rp_goals = []
  end
end
