class WeeklyCheckinsController < ApplicationController
  def show
    @week_start = Date.current.beginning_of_week(:monday)
    @last_week_start = @week_start - 7.days
    @last_week_goals = current_user.weekly_goals.for_week(@last_week_start)
    @this_week_goals = current_user.weekly_goals.for_week(@week_start)
    @step = params[:step].to_i.clamp(1, 2)
    @step = 1 if @step < 1
  end

  def update
    @week_start = Date.current.beginning_of_week(:monday)
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
      # Upsert this week's goals — update existing rows, create new ones, skip blanks.
      goal_titles = Array(params[:goals]).map(&:strip).reject(&:blank?)
      existing = current_user.weekly_goals.for_week(@week_start).order(:id).to_a

      goal_titles.each_with_index do |title, i|
        if existing[i]
          existing[i].update!(title: title) if existing[i].title != title
        else
          current_user.weekly_goals.create!(title: title, week_start_date: @week_start)
        end
      end

      # Remove extra goals if the user submitted fewer than existed before.
      existing[goal_titles.size..].each(&:destroy!) if existing.size > goal_titles.size

      redirect_to ritual_morning_path, notice: "Goals set. Now let's plan the week."

    else
      redirect_to weekly_checkin_path(step: 1), status: :see_other
    end
  end
end
