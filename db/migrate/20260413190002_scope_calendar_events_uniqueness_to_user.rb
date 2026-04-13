# frozen_string_literal: true

class ScopeCalendarEventsUniquenessToUser < ActiveRecord::Migration[8.1]
  def change
    remove_index :calendar_events, name: "index_calendar_events_on_external_id_and_source"
    add_index :calendar_events, [ :user_id, :external_id, :source ],
      unique: true,
      name: "index_calendar_events_on_user_external_and_source"
  end
end
