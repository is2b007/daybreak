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
    @rp_bc_tasks = current_user.task_assignments.basecamp.incomplete.for_week(week_start).ordered.limit(20)
    @rp_hey_tasks = current_user.task_assignments.hey.incomplete.for_week(week_start).ordered.limit(20)
    @rp_goals = current_user.weekly_goals.where(week_start_date: week_start)
  rescue => e
    Rails.logger.warn "Right panel data load failed: #{e.message}"
    @rp_bc_tasks = []
    @rp_hey_tasks = []
    @rp_goals = []
  end
end
