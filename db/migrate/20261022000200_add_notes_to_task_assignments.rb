class AddNotesToTaskAssignments < ActiveRecord::Migration[8.1]
  # Basecamp sync owns `description` for synced to-dos and cards, so the
  # user's private notes need their own column or the next sync clobbers them.
  def change
    add_column :task_assignments, :notes, :text
  end
end
