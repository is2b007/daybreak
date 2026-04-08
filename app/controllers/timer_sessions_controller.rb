class TimerSessionsController < ApplicationController
  def create
    # Stop any running timer first
    current_user.local_timer_sessions.running.each(&:stop!)

    @timer = current_user.local_timer_sessions.create!(
      task_assignment_id: params[:task_assignment_id],
      started_at: Time.current
    )
    redirect_back fallback_location: day_path(Date.current)
  end

  def update
    @timer = current_user.local_timer_sessions.find(params[:id])
    @timer.stop!
    redirect_back fallback_location: day_path(Date.current)
  end
end
