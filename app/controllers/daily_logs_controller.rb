class DailyLogsController < ApplicationController
  # A hand-edited or stale URL shouldn't 500 the log.
  rescue_from Date::Error, with: :redirect_to_today

  def show
    redirect_to day_path(parsed_date, tab: "log")
  end

  def create
    @date = parsed_date
    @daily_log = current_user.daily_logs.find_or_create_by!(date: @date)
    append_entry
  end

  def update
    @date = parsed_date
    @daily_log = current_user.daily_logs.find_by!(date: @date)
    append_entry
  end

  private

  def parsed_date
    Date.parse(params[:date])
  end

  # An empty submit fails LogEntry's content presence validation and 500s; treat it
  # as a no-op and send the user back to the log they were looking at.
  def append_entry
    content = params[:content].to_s.strip
    if content.blank?
      redirect_to day_path(@date, tab: "log"), alert: "Nothing to log yet."
      return
    end

    @daily_log.log_entries.create!(content: content, logged_at: Time.current)
    redirect_to day_path(@date, tab: "log")
  end

  def redirect_to_today
    redirect_to day_path(current_user.today_in_zone, tab: "log"), alert: "That date didn't look right."
  end
end
