class AddHeyAppUrlToTaskAssignments < ActiveRecord::Migration[8.1]
  def change
    add_column :task_assignments, :hey_app_url, :string
  end
end
