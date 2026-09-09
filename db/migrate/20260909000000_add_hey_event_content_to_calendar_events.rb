class AddHeyEventContentToCalendarEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :calendar_events, :hey_event_url, :string
    add_column :calendar_events, :hey_entry_id, :string
  end
end
