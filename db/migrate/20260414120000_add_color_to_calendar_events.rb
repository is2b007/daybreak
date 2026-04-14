class AddColorToCalendarEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :calendar_events, :color, :string
  end
end
