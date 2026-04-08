class RitualsController < ApplicationController
  def morning
    @date = Date.current
    @step = (params[:step] || 1).to_i
    @day_plan = current_user.day_plans.find_or_create_by!(date: @date)

    case @step
    when 1 then load_yesterdays_loose_ends
    when 2 then load_todays_schedule
    when 3 then load_available_tasks
    when 4 then nil # Free text step
    when 5 then load_day_summary
    end
  end

  def morning_update
    @date = Date.current
    @step = params[:step].to_i
    @day_plan = current_user.day_plans.find_or_create_by!(date: @date)

    case @step
    when 1
      process_yesterday_decisions
      redirect_to ritual_morning_path(step: 2)
    when 2
      redirect_to ritual_morning_path(step: 3)
    when 3
      process_task_selections
      redirect_to ritual_morning_path(step: 4)
    when 4
      create_personal_task if params[:personal_task].present?
      redirect_to ritual_morning_path(step: 5)
    end
  end

  def morning_complete
    @day_plan = current_user.day_plans.find_or_create_by!(date: Date.current)
    @day_plan.update!(morning_ritual_done: true, status: :active)
    current_user.record_open!
    redirect_to day_path(Date.current), notice: "Your day is set."
  end

  def evening
    @date = Date.current
    @step = (params[:step] || 1).to_i
    @day_plan = current_user.day_plans.find_by(date: @date)

    case @step
    when 1 then load_completed_tasks
    when 2 then load_remaining_tasks
    when 3 then nil # Reflection step
    end
  end

  def evening_update
    @date = Date.current
    @step = params[:step].to_i

    case @step
    when 1
      redirect_to ritual_evening_path(step: 2)
    when 2
      process_evening_decisions
      redirect_to ritual_evening_path(step: 3)
    when 3
      save_reflection
      redirect_to ritual_evening_complete_path
    end
  end

  def evening_complete
    @day_plan = current_user.day_plans.find_by(date: Date.current)
    @day_plan&.update!(evening_ritual_done: true, status: :completed)

    # Sync daily log to HEY Journal if connected
    SyncJournalJob.perform_later(current_user.id, Date.current.to_s) if current_user.hey_connected?

    redirect_to root_path
  end

  private

  def load_yesterdays_loose_ends
    yesterday_plan = current_user.day_plans.find_by(date: Date.yesterday)
    @yesterday_tasks = yesterday_plan ? yesterday_plan.task_assignments.incomplete : TaskAssignment.none
  end

  def load_todays_schedule
    @calendar_events = current_user.calendar_events
      .for_date(@date)
      .chronological
      .map(&:to_view_hash)

    @basecamp_assignments = current_user.task_assignments
      .basecamp
      .incomplete
      .where("created_at > ?", 1.week.ago)
      .limit(5)
      .map { |t| { title: t.title, due_on: nil } }

    @hey_todos = current_user.task_assignments
      .hey
      .incomplete
      .where("created_at > ?", 1.week.ago)
      .limit(5)
      .map { |t| { title: t.title } }
  end

  def load_available_tasks
    @available_tasks = current_user.task_assignments
      .where(day_plan: @day_plan)
      .or(current_user.task_assignments.sometime.for_week(@date.beginning_of_week(:monday)))
      .incomplete
      .ordered
  end

  def load_day_summary
    @tasks = @day_plan.task_assignments.ordered
    @total_planned = @tasks.sum(:planned_duration_minutes).to_i
    @work_hours = current_user.work_hours_target * 60
    @overfull = @total_planned > @work_hours
  end

  def load_completed_tasks
    @completed_tasks = @day_plan ? @day_plan.task_assignments.completed : TaskAssignment.none
  end

  def load_remaining_tasks
    @remaining_tasks = @day_plan ? @day_plan.task_assignments.incomplete : TaskAssignment.none
  end

  def process_yesterday_decisions
    return unless params[:tasks].present?

    params[:tasks].each do |task_id, decision|
      task = current_user.task_assignments.find_by(id: task_id)
      next unless task

      case decision
      when "done"
        task.complete!
      when "today"
        today_plan = current_user.day_plans.find_or_create_by!(date: Date.current)
        task.update!(day_plan: today_plan, week_start_date: Date.current.beginning_of_week(:monday))
      when "let_go"
        task.update!(status: :deferred, day_plan: nil, week_bucket: "sometime")
      end
    end
  end

  def process_task_selections
    return unless params[:selected_tasks].present?

    params[:selected_tasks].each_with_index do |task_id, index|
      task = current_user.task_assignments.find_by(id: task_id)
      next unless task

      task.update!(
        day_plan: @day_plan,
        position: index,
        size: params.dig(:sizes, task_id.to_s) || task.size,
        planned_duration_minutes: params.dig(:durations, task_id.to_s)&.to_i
      )
    end
  end

  def create_personal_task
    today_plan = current_user.day_plans.find_or_create_by!(date: Date.current)
    current_user.task_assignments.create!(
      title: params[:personal_task],
      source: :local,
      day_plan: today_plan,
      week_start_date: Date.current.beginning_of_week(:monday),
      week_bucket: "day",
      position: today_plan.task_assignments.count
    )
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
