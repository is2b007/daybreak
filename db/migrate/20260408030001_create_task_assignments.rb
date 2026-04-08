class CreateTaskAssignments < ActiveRecord::Migration[8.1]
  def change
    create_table :task_assignments do |t|
      t.references :user, null: false, foreign_key: true
      t.references :day_plan, foreign_key: true
      t.string :external_id
      t.integer :source, default: 0, null: false
      t.string :title, null: false
      t.text :description
      t.integer :size, default: 1, null: false
      t.integer :position
      t.integer :planned_duration_minutes
      t.integer :actual_duration_minutes
      t.integer :status, default: 0, null: false
      t.datetime :completed_at
      t.integer :stamp_rotation_degrees
      t.string :week_bucket, default: "day", null: false
      t.date :week_start_date
      t.string :basecamp_bucket_id
      t.string :project_name

      t.timestamps
    end

    add_index :task_assignments, [ :user_id, :day_plan_id ]
    add_index :task_assignments, [ :user_id, :week_start_date ]
    add_index :task_assignments, [ :external_id, :source ]
  end
end
