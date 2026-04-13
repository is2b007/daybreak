class AddHeyMirroredTodoIdToTaskAssignments < ActiveRecord::Migration[8.1]
  def change
    add_column :task_assignments, :hey_mirrored_todo_id, :string
    add_index :task_assignments, :hey_mirrored_todo_id
  end
end
