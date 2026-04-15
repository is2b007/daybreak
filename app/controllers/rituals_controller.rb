class RitualsController < ApplicationController
  def morning
    @date = Date.current
    @step = (params[:step] || 1).to_i
    unless [ 1, 2 ].include?(@step)
      redirect_to ritual_morning_path(step: 1), status: :see_other
      return
    end

    @day_plan = current_user.day_plans.find_or_create_by!(date: @date)
    # Play sunrise animation + sound once per day on step 1.
    # Record the open immediately so a page refresh doesn't replay the animation.
    @play_sunrise = @step == 1 && current_user.first_open_today?
    current_user.record_open! if @play_sunrise

    case @step
    when 1
      load_yesterday_review
    when 2
      load_today_planning_context
    end
  end

  def morning_update
    @date = Date.current
    case params[:step].to_i
    when 1
      redirect_to ritual_morning_path(step: 2, plan: "1"), status: :see_other
    when 2
      @day_plan = current_user.day_plans.find_or_create_by!(date: @date)
      @day_plan.update!(morning_ritual_done: true, status: :active)
      current_user.record_open!
      redirect_to day_path(Date.current), notice: "You're set. Have a good day."
    else
      redirect_to ritual_morning_path(step: 1), status: :see_other
    end
  end

  def morning_complete
    redirect_to day_path(Date.current), notice: "Your day is set."
  end

  def morning_add_week_events
    @date = Date.current
    scope = current_user.calendar_events.for_date(@date, current_user.timezone).where(show_on_week_board: false)
    n = scope.update_all(show_on_week_board: true)
    notice = if n.positive?
      "#{n} #{'item'.pluralize(n)} added to your week view."
    else
      "Everything visible is already on your week view."
    end
    redirect_to ritual_morning_path(step: 2, plan: params[:plan]), notice: notice
  end

  def evening
    @date = Date.current
    @step = (params[:step] || 1).to_i
    @day_plan = current_user.day_plans.find_by(date: @date)

    case @step
    when 1
      load_evening_dashboard
    when 2
      nil # reflection
    else
      redirect_to ritual_evening_path(step: 1), status: :see_other
    end
  end

  def evening_update
    @date = Date.current
    case params[:step].to_i
    when 1
      process_evening_decisions
      redirect_to ritual_evening_path(step: 2), status: :see_other
    when 2
      save_reflection
      redirect_to ritual_evening_complete_path, status: :see_other
    else
      redirect_to ritual_evening_path(step: 1), status: :see_other
    end
  end

  def evening_complete
    @day_plan = current_user.day_plans.find_by(date: Date.current)
    @day_plan&.update!(evening_ritual_done: true, status: :completed)

    # Sync daily log to HEY Journal if connected
    SyncJournalJob.perform_later(current_user.id, Date.current.to_s) if current_user.hey_connected?

    render :evening_wrap
  end

  private

  def load_yesterday_review
    load_yesterday_wins
    @yesterday_tracked_min = yesterday_tracked_minutes
    @yesterday_scale_min = (current_user.work_hours_target * 60).to_i
  end

  def yesterday_tracked_minutes
    tz = Time.find_zone(current_user.timezone) || Time.zone
    day_start = Date.yesterday.in_time_zone(tz).beginning_of_day
    day_end = Date.yesterday.in_time_zone(tz).end_of_day

    from_timers = current_user.local_timer_sessions
      .where.not(ended_at: nil)
      .where(started_at: day_start..day_end)
      .sum(&:duration_minutes)

    return from_timers if from_timers.positive?

    yesterday_plan = current_user.day_plans.find_by(date: Date.yesterday)
    return 0 unless yesterday_plan

    yesterday_plan.task_assignments.completed.sum(:actual_duration_minutes).to_i
  end

  def load_today_planning_context
    @tasks = @day_plan.task_assignments.ordered
    @calendar_events = fetch_calendar_events_for_date(@date)
    @calendar_chips = CalendarEvent.day_view_chip_records(current_user, @date).map(&:to_view_hash)
    @plan_mode = params[:plan].present?
    @tab = "tasks"
  end

  def fetch_calendar_events_for_date(date)
    tz = current_user.timezone
    current_user.calendar_events
      .for_date(date, tz)
      .chronological
      .map { |e| e.to_timeline_hash(tz) }
      .compact
      .reject { |h| h[:all_day] }
  end

  def load_yesterday_wins
    yesterday_plan = current_user.day_plans.find_by(date: Date.yesterday)
    @yesterday_wins = if yesterday_plan
      yesterday_plan.task_assignments.completed.order(Arel.sql("COALESCE(completed_at, updated_at) DESC"))
    else
      TaskAssignment.none
    end
  end

  def load_completed_tasks
    @completed_tasks = @day_plan ? @day_plan.task_assignments.completed : TaskAssignment.none
  end

  def load_remaining_tasks
    @remaining_tasks = @day_plan ? @day_plan.task_assignments.incomplete : TaskAssignment.none
  end

  def load_evening_dashboard
    load_completed_tasks
    load_remaining_tasks
    @completed_tasks = @completed_tasks.order(Arel.sql("COALESCE(completed_at, updated_at) DESC"))
    @remaining_tasks = @remaining_tasks.order(:position)
    @evening_actual_minutes = today_tracked_or_actual_minutes
    @evening_planned_minutes = today_planned_minutes_total
    @donut_segments = today_time_by_project_segments
  end

  def today_planned_minutes_total
    return 0 unless @day_plan

    @day_plan.task_assignments.sum { |t| (t.planned_duration_minutes || 60).to_i }
  end

  def today_tracked_or_actual_minutes
    return 0 unless @day_plan

    tz = Time.find_zone(current_user.timezone) || Time.zone
    range = Date.current.in_time_zone(tz).all_day
    from_timers = current_user.local_timer_sessions
      .where.not(ended_at: nil)
      .where(started_at: range)
      .sum(&:duration_minutes)
    return from_timers if from_timers.positive?

    @day_plan.task_assignments.sum { |t| t.actual_duration_minutes.to_i }
  end

  def today_time_by_project_segments
    return [] unless @day_plan

    hash = Hash.new(0)
    @day_plan.task_assignments.each do |t|
      mins = t.actual_duration_minutes.to_i
      if mins <= 0 && t.completed?
        mins = (t.planned_duration_minutes || 60).to_i
      end
      next if mins <= 0

      label = t.project_name.presence
      label ||= t.hey? ? "HEY" : (t.local? ? "Local" : t.source.to_s.titleize)
      hash[label] += mins
    end

    colors = %w[#7c3aed #a855f7 #c084fc #9333ea #6b21a8 #5b21b6]
    hash.sort_by { |_k, v| -v }.map.with_index do |(label, minutes), i|
      { label: label, minutes: minutes, color: colors[i % colors.size] }
    end
  end

  def process_evening_decisions
    return unless params[:tasks].present?

    params[:tasks].each do |task_id, decision|
      task = current_user.task_assignments.find_by(id: task_id)
      next unless task

      case decision
      when "tomorrow"
        task.defer_to_tomorrow!
      when "sometime"
        task.defer_to_sometime!
        SyncSometimeTodoToHeyJob.perform_later(task.id) if current_user.hey_connected? && !Rails.env.test?
      when "let_go"
        task.update!(status: :deferred)
      end
    end
  end

  def save_reflection
    return unless params[:reflection].present?

    if current_user.hey_connected?
      # Will sync via SyncJournalJob
    end

    # Always save locally
    entry = current_user.local_journal_entries.find_or_initialize_by(date: Date.current)
    entry.update!(content: params[:reflection])
  end
end
