class WeeklyCheckinsController < ApplicationController
  def show
    @week_start = current_user.current_week_start
    @last_week_start = @week_start - 7.days
    @last_week_goals = current_user.weekly_goals.for_week(@last_week_start)
    @this_week_goals = current_user.weekly_goals.for_week(@week_start)
    @step = params[:step].to_i.clamp(1, 2)
    @step = 1 if @step < 1
  end

  def update
    @week_start = current_user.current_week_start
    @step = params[:step].to_i

    case @step
    when 1
      # Mark last week's goals: checked ones as completed, unchecked as not completed.
      last_week_start = @week_start - 7.days
      completed_ids = Array(params[:completed_goals]).map(&:to_i).to_set
      current_user.weekly_goals.for_week(last_week_start).each do |goal|
        goal.update!(completed: completed_ids.include?(goal.id))
      end
      redirect_to weekly_checkin_path(step: 2), status: :see_other

    when 2
      upsert_this_weeks_goals
      redirect_to ritual_morning_path, notice: "Goals set. Now let's plan the week."

    else
      redirect_to weekly_checkin_path(step: 1), status: :see_other
    end
  end

  private

  # Position-keyed upsert: each slot (0..3) corresponds to a goal input row.
  # Wrapped in a transaction and anchored by a unique (user, week, position) index so
  # a double-submit during network lag can't create duplicate rows.
  def upsert_this_weeks_goals
    goal_titles = Array(params[:goals]).map(&:strip).reject(&:blank?)

    ActiveRecord::Base.transaction do
      goal_titles.each_with_index do |title, position|
        goal = current_user.weekly_goals
          .find_or_initialize_by(week_start_date: @week_start, position: position)
        goal.title = title
        goal.save!
      end

      # Trim any slots beyond what was submitted (user removed a goal).
      current_user.weekly_goals
        .where(week_start_date: @week_start)
        .where("position >= ?", goal_titles.size)
        .destroy_all
    end
  end
end
