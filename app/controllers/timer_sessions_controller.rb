class TimerSessionsController < ApplicationController
  def create
    # Stop any running timer first
    current_user.local_timer_sessions.running.each(&:stop!)

    task = params[:task_assignment_id].present? ? current_user.task_assignments.find(params[:task_assignment_id]) : nil

    @timer = current_user.local_timer_sessions.create!(
      task_assignment_id: task&.id,
      started_at: Time.current
    )

    # Start HEY time tracking if connected
    if current_user.hey_connected? && task
      begin
        client = HeyClient.new(current_user)
        result = client.start_time_track(title: task.title)
        if result.is_a?(Hash) && result["id"].present?
          @timer.update_column(:hey_time_track_id, result["id"].to_s)
        end
      rescue StandardError => e
        Rails.logger.warn("HEY time track start failed: #{e.message}")
      end
    end

    redirect_back fallback_location: day_path(Date.current)
  end

  def update
    @timer = current_user.local_timer_sessions.find(params[:id])

    # Stop HEY time tracking if we started one
    if @timer.hey_time_track_id.present? && current_user.hey_connected?
      begin
        client = HeyClient.new(current_user)
        client.stop_time_track(@timer.hey_time_track_id)
      rescue StandardError => e
        Rails.logger.warn("HEY time track stop failed: #{e.message}")
      end
    end

    @timer.stop!
    redirect_back fallback_location: day_path(Date.current)
  end
end
