class DailyLogsController < ApplicationController
  def show
    @date = Date.parse(params[:date])
    @daily_log = current_user.daily_logs.find_or_initialize_by(date: @date)
    @log_entries = @daily_log.persisted? ? @daily_log.log_entries.order(:logged_at) : []
  end

  def create
    @date = Date.parse(params[:date])
    @daily_log = current_user.daily_logs.find_or_create_by!(date: @date)
    @daily_log.log_entries.create!(
      content: params[:content],
      logged_at: Time.current
    )
    redirect_to day_path(@date, tab: "log")
  end

  def update
    @date = Date.parse(params[:date])
    @daily_log = current_user.daily_logs.find_by!(date: @date)
    @daily_log.log_entries.create!(
      content: params[:content],
      logged_at: Time.current
    )
    redirect_to day_path(@date, tab: "log")
  end
end
