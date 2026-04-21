class WeeksController < ApplicationController
  INITIAL_DAYS = 14
  BATCH_DAYS   = 7

  def show
    @window_start    = parse_window_start
    data             = fetch_window_data(@window_start, INITIAL_DAYS)
    @window_dates    = data[:dates]
    @window_end      = @window_dates.last
    @tasks_by_day    = data[:tasks_by_day]
    @calendar_events = data[:calendar_events]
    @display_end     = @window_start + 6.days

    week_starts = [ @window_start.beginning_of_week(:monday),
                    @window_end.beginning_of_week(:monday) ].uniq

    @task_assignments = current_user.task_assignments
      .includes(:day_plan)
      .left_joins(:day_plan)
      .where(
        "(day_plans.date BETWEEN :start_date AND :end_date) OR (task_assignments.week_bucket = :sometime AND task_assignments.week_start_date IN (:week_starts))",
        start_date: @window_start,
        end_date: @window_end,
        sometime: "sometime",
        week_starts: week_starts
      )
      .ordered

    @sometime_tasks = @task_assignments.sometime
    @weekly_goals   = current_user.weekly_goals.for_week(@window_start.beginning_of_week(:monday))
  end

  def days
    from             = parse_from_param
    data             = fetch_window_data(from, BATCH_DAYS)
    @batch_dates     = data[:dates]
    @tasks_by_day    = data[:tasks_by_day]
    @calendar_events = data[:calendar_events]
    @next_from       = from + BATCH_DAYS.days

    respond_to do |format|
      format.turbo_stream
    end
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

  def parse_from_param
    date = Date.parse(params[:from])
    date = Date.current if date > Date.current + 90.days
    date
  rescue Date::Error, TypeError
    Date.current
  end

  def fetch_window_data(from_date, num_days)
    to_date = from_date + (num_days - 1).days
    dates   = (from_date..to_date).to_a

    task_assignments = current_user.task_assignments
      .includes(:day_plan)
      .left_joins(:day_plan)
      .where(
        "(day_plans.date BETWEEN :s AND :e) OR (task_assignments.week_bucket = :sometime AND task_assignments.week_start_date IN (:ws))",
        s: from_date, e: to_date, sometime: "sometime",
        ws: [ from_date.beginning_of_week(:monday), to_date.beginning_of_week(:monday) ].uniq
      )
      .ordered

    calendar_events = current_user.calendar_events
      .pinned_to_week_board
      .where(starts_at: from_date.beginning_of_day..to_date.end_of_day)
      .chronological
      .group_by { |e| e.all_day ? e.starts_at.utc.to_date : e.starts_at.in_time_zone(current_user.timezone).to_date }
      .transform_values { |evs| evs.map(&:to_view_hash) }

    {
      dates:          dates,
      tasks_by_day:   task_assignments.for_day.group_by { |ta| ta.day_plan&.date },
      calendar_events: calendar_events
    }
  end

  def fetch_calendar_events
    current_user.calendar_events
      .pinned_to_week_board
      .where(starts_at: @window_start.beginning_of_day..@window_end.end_of_day)
      .chronological
      .group_by { |e| e.all_day ? e.starts_at.utc.to_date : e.starts_at.in_time_zone(current_user.timezone).to_date }
      .transform_values { |events| events.map(&:to_view_hash) }
  end
end
