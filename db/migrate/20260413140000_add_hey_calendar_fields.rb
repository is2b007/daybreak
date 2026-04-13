class AddHeyCalendarFields < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :hey_default_calendar_id, :string
    add_column :calendar_events, :hey_calendar_id, :string
  end
end
