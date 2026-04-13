class DaysController < ApplicationController
  def show
    @date = Date.parse(params[:date])
    @day_plan = current_user.day_plans.find_or_create_by!(date: @date)
    @tasks = @day_plan.task_assignments.ordered
    @completed_tasks = @tasks.completed
    @pending_tasks = @tasks.incomplete
    @calendar_events = fetch_calendar_events
    @calendar_chips = current_user.calendar_events.for_date(@date).chronological.map(&:to_view_hash)
    @daily_log = current_user.daily_logs.find_or_initialize_by(date: @date)
    @log_entries = @daily_log.persisted? ? @daily_log.log_entries.order(:logged_at) : []
    @journal_entry = current_user.local_journal_entries.find_by(date: @date)
    @journal_hey_synced = @journal_entry.present? &&
      @journal_entry.last_pushed_to_hey_digest.present? &&
      @journal_entry.last_pushed_to_hey_digest == @journal_entry.content_digest
    @tab = params[:tab] || "tasks"
    @plan_mode = params[:plan].present?

    if !Rails.env.test? && (current_user.basecamp_access_token.present? || current_user.hey_connected?)
      SyncCalendarEventsJob.perform_later(
        current_user.id,
        week_start: @date.beginning_of_week(:monday).iso8601
      )
    end
    if !Rails.env.test? && current_user.hey_connected? &&
        !Rails.cache.exist?("journal_local_push:#{current_user.id}:#{@date}")
      ImportHeyJournalJob.perform_later(current_user.id, @date.to_s)
    end
  rescue Date::Error
    redirect_to root_path
  end

  private

  def fetch_calendar_events
    tz = current_user.timezone
    current_user.calendar_events
      .for_date(@date)
      .chronological
      .map { |e| e.to_timeline_hash(tz) }
      .compact
  end
end
