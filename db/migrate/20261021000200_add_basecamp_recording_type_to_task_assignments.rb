class AddBasecampRecordingTypeToTaskAssignments < ActiveRecord::Migration[8.1]
  def change
    add_column :task_assignments, :basecamp_recording_type, :string
  end
end
