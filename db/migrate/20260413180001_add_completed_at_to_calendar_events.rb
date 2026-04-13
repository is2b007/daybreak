class AddCompletedAtToCalendarEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :calendar_events, :completed_at, :datetime
  end
end
