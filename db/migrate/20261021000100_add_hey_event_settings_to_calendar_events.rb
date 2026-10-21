class AddHeyEventSettingsToCalendarEvents < ActiveRecord::Migration[8.1]
  def change
    # HEY clears reminders and resets the zone on any update that leaves them out, so
    # sync keeps them to send back when an event is moved on the timeline.
    add_column :calendar_events, :hey_reminder_seconds, :text
    add_column :calendar_events, :hey_time_zone, :string
  end
end
