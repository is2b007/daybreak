class WeeksController < ApplicationController
  def show
    @week_start = parse_week_start
    @week_dates = (0..6).map { |i| @week_start + i.days }
    @day_plans = current_user.day_plans
      .for_week(@week_start)
      .index_by(&:date)
    @task_assignments = current_user.task_assignments
      .for_week(@week_start)
      .includes(:day_plan)
      .ordered
    @tasks_by_day = @task_assignments.for_day.group_by { |ta| ta.day_plan&.date }
    @sometime_tasks = @task_assignments.sometime
    @weekly_goals = current_user.weekly_goals.for_week(@week_start)
    @calendar_events = fetch_calendar_events
  end

  private

  def parse_week_start
    if params[:date].present?
      Date.parse(params[:date]).beginning_of_week(:monday)
    else
      Date.current.beginning_of_week(:monday)
    end
  rescue Date::Error
    Date.current.beginning_of_week(:monday)
  end

  def fetch_calendar_events
    # TODO: Fetch from Basecamp schedules and HEY Calendar
    # Returns empty hash for now, keyed by date
    {}
  end
end
