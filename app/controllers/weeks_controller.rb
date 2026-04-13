class WeeksController < ApplicationController
  WINDOW_DAYS = 4

  def show
    @window_start = parse_window_start
    @window_end = @window_start + (WINDOW_DAYS - 1).days
    @window_dates = (@window_start..@window_end).to_a

    @day_plans = current_user.day_plans
      .where(date: @window_start..@window_end)
      .index_by(&:date)

    window_week_starts = [ @window_start.beginning_of_week(:monday), @window_end.beginning_of_week(:monday) ].uniq

    @task_assignments = current_user.task_assignments
      .includes(:day_plan)
      .left_joins(:day_plan)
      .where(
        "(day_plans.date BETWEEN :start_date AND :end_date) OR (task_assignments.week_bucket = :sometime AND task_assignments.week_start_date IN (:week_starts))",
        start_date: @window_start,
        end_date: @window_end,
        sometime: "sometime",
        week_starts: window_week_starts
      )
      .ordered

    @tasks_by_day = @task_assignments.for_day.group_by { |ta| ta.day_plan&.date }
    @sometime_tasks = @task_assignments.sometime
    @weekly_goals = current_user.weekly_goals.for_week(@window_start.beginning_of_week(:monday))
    @calendar_events = fetch_calendar_events
  end

  private

  def parse_window_start
    if params[:date].present?
      Date.parse(params[:date])
    else
      Date.current
    end
  rescue Date::Error
    Date.current
  end

  def fetch_calendar_events
    current_user.calendar_events
      .pinned_to_week_board
      .where(starts_at: @window_start.beginning_of_day..@window_end.end_of_day)
      .chronological
      .group_by { |e| e.starts_at.in_time_zone(current_user.timezone).to_date }
      .transform_values { |events| events.map(&:to_view_hash) }
  end
end
