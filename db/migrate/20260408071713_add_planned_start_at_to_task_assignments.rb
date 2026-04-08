class AddPlannedStartAtToTaskAssignments < ActiveRecord::Migration[8.1]
  def change
    add_column :task_assignments, :planned_start_at, :datetime
    add_column :task_assignments, :hey_calendar_event_id, :string
    add_index :task_assignments, [ :user_id, :planned_start_at ]
  end
end
