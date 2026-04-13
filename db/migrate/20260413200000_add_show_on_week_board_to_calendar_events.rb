class AddShowOnWeekBoardToCalendarEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :calendar_events, :show_on_week_board, :boolean, default: false, null: false
    add_index :calendar_events, [ :user_id, :show_on_week_board ],
      name: "index_calendar_events_on_user_id_and_show_on_week_board"
  end
end
