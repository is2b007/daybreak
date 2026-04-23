class RitualsController < ApplicationController
  def morning
    @date = current_user.today_in_zone
    @step = (params[:step] || 1).to_i
    unless [ 1, 2 ].include?(@step)
      redirect_to ritual_morning_path(step: 1), status: :see_other
      return
    end

    @day_plan = current_user.day_plans.find_or_create_by!(date: @date)
    # Snapshot before writing so a reload in-flight can't replay the animation.
    @play_sunrise = @step == 1 && current_user.first_open_today?
    current_user.record_open!

    case @step
    when 1
      load_yesterday_review
    when 2
      load_today_planning_context
    end
  end

  def morning_update
    @date = current_user.today_in_zone
    case params[:step].to_i
    when 1
      redirect_to ritual_morning_path(step: 2, plan: "1"), status: :see_other
    when 2
      @day_plan = current_user.day_plans.find_or_create_by!(date: @date)
      @day_plan.update!(morning_ritual_done: true, status: :active)
      current_user.record_open!
      redirect_to day_path(@date), notice: "You're set. Have a good day."
    else
      redirect_to ritual_morning_path(step: 1), status: :see_other
    end
  end

  def morning_complete
    redirect_to day_path(current_user.today_in_zone), notice: "Your day is set."
  end

  def morning_add_week_events
    @date = current_user.today_in_zone
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
    @date = current_user.today_in_zone
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
    @date = current_user.today_in_zone
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
    today = current_user.today_in_zone
    @day_plan = current_user.day_plans.find_by(date: today)
    @day_plan&.update!(evening_ritual_done: true, status: :completed)

    # Sync daily log to HEY Journal if connected
    SyncJournalJob.perform_later(current_user.id, today.to_s) if current_user.hey_connected?

    # Play the sunset animation+sound once per day; a reload of /ritual/evening/complete
    # should not re-trigger it.
    @play_sunset = !current_user.sunset_already_played_today?
    current_user.record_sunset_played!

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
    yesterday_local = current_user.today_in_zone - 1.day
    range = yesterday_local.in_time_zone(tz).all_day

    from_timers = tracked_minutes_in_range(range)
    return from_timers if from_timers.positive?

    yesterday_plan = current_user.day_plans.find_by(date: yesterday_local)
    return 0 unless yesterday_plan

    yesterday_plan.task_assignments.completed.sum(:actual_duration_minutes).to_i
  end

  # Sums timer durations at the DB layer via pluck (avoids AR object instantiation).
  # Kept in Ruby because SQLite lacks a clean portable way to round (ended_at - started_at)
  # to minutes; pluck is still O(N) but ~40x cheaper than .sum(&:duration_minutes).
  def tracked_minutes_in_range(range)
    current_user.local_timer_sessions
      .where.not(ended_at: nil)
      .where(started_at: range)
      .pluck(:started_at, :ended_at)
      .sum { |s, e| ((e - s) / 60.0).round }
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
    yesterday_plan = current_user.day_plans.find_by(date: current_user.today_in_zone - 1.day)
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

    @day_plan.task_assignments.sum("COALESCE(planned_duration_minutes, 60)").to_i
  end

  def today_tracked_or_actual_minutes
    return 0 unless @day_plan

    tz = Time.find_zone(current_user.timezone) || Time.zone
    range = current_user.today_in_zone.in_time_zone(tz).all_day
    from_timers = tracked_minutes_in_range(range)
    return from_timers if from_timers.positive?

    @day_plan.task_assignments.sum("COALESCE(actual_duration_minutes, 0)").to_i
  end

  def today_time_by_project_segments
    return [] unless @day_plan

    rows = @day_plan.task_assignments.pluck(
      :project_name, :source, :actual_duration_minutes, :planned_duration_minutes, :status
    )
    completed_status = TaskAssignment.statuses[:completed]
    hey_source = TaskAssignment.sources[:hey]
    local_source = TaskAssignment.sources[:local]

    hash = Hash.new(0)
    rows.each do |project_name, source, actual, planned, status|
      mins = actual.to_i
      mins = (planned || 60).to_i if mins <= 0 && status == completed_status
      next if mins <= 0

      label = project_name.presence
      label ||= case source
      when hey_source then "HEY"
      when local_source then "Local"
      else TaskAssignment.sources.key(source).to_s.titleize
      end
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

    # Always save locally (HEY sync fires from evening_complete via SyncJournalJob)
    entry = current_user.local_journal_entries.find_or_initialize_by(date: current_user.today_in_zone)
    entry.update!(content: params[:reflection])
  end
end
