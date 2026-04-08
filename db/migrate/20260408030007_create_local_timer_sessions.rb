class CreateLocalTimerSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :local_timer_sessions do |t|
      t.references :user, null: false, foreign_key: true
      t.references :task_assignment, foreign_key: true
      t.datetime :started_at, null: false
      t.datetime :ended_at

      t.timestamps
    end
  end
end
