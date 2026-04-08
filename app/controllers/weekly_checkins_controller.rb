class WeeklyCheckinsController < ApplicationController
  def show
    @week_start = Date.current.beginning_of_week(:monday)
    @last_week_start = @week_start - 7.days
    @last_week_goals = current_user.weekly_goals.for_week(@last_week_start)
    @this_week_goals = current_user.weekly_goals.for_week(@week_start)
  end

  def update
    @week_start = Date.current.beginning_of_week(:monday)

    # Update last week's goal completions
    if params[:completed_goals].present?
      params[:completed_goals].each do |goal_id|
        goal = current_user.weekly_goals.find_by(id: goal_id)
        goal&.update!(completed: true)
      end
    end

    # Create new goals
    if params[:goals].present?
      params[:goals].each do |goal_text|
        next if goal_text.blank?
        current_user.weekly_goals.create!(
          title: goal_text.strip,
          week_start_date: @week_start
        )
      end
    end

    redirect_to ritual_morning_path, notice: "Goals set. Let's plan Monday."
  end
end
