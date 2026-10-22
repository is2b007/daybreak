class AddBasecampColumnToTaskAssignments < ActiveRecord::Migration[8.1]
  def change
    add_column :task_assignments, :basecamp_column_id, :string
    add_column :task_assignments, :basecamp_column_name, :string
  end
end
