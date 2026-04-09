class DaysController < ApplicationController
  def show
    @date = Date.parse(params[:date])
    @day_plan = current_user.day_plans.find_or_create_by!(date: @date)
    @tasks = @day_plan.task_assignments.ordered
    @completed_tasks = @tasks.completed
    @pending_tasks = @tasks.incomplete
    @calendar_events = fetch_calendar_events
    @daily_log = current_user.daily_logs.find_or_initialize_by(date: @date)
    @log_entries = @daily_log.persisted? ? @daily_log.log_entries.order(:logged_at) : []
    @journal_entry = current_user.local_journal_entries.find_by(date: @date)
    @active_timer = current_user.local_timer_sessions.running.first
    @tab = params[:tab] || "tasks"
  rescue Date::Error
    redirect_to root_path
  end

  private

  def fetch_calendar_events
    current_user.calendar_events
      .for_date(@date)
      .chronological
      .map(&:to_view_hash)
  end
end
