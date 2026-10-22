class WeeklyGoalsController < ApplicationController
  # Ticks a goal off (or back on) from the side panel.
  def update
    goal = current_user.weekly_goals.find(params[:id])
    goal.update!(completed: ActiveModel::Type::Boolean.new.cast(params.require(:completed)))
    redirect_back fallback_location: root_path
  end
end
