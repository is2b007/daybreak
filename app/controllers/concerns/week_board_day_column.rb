# Calendar chips on the week kanban: only events the user pinned from the day timeline or sunrise.
module WeekBoardDayColumn
  extend ActiveSupport::Concern

  private

  def day_column_calendar_events_for(user, date)
    user.calendar_events
      .pinned_to_week_board
      .where(starts_at: date.beginning_of_day..date.end_of_day)
      .chronological
      .map(&:to_view_hash)
  end
end
