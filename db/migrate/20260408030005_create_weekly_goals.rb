class CreateWeeklyGoals < ActiveRecord::Migration[8.1]
  def change
    create_table :weekly_goals do |t|
      t.references :user, null: false, foreign_key: true
      t.date :week_start_date, null: false
      t.string :title, null: false
      t.boolean :completed, default: false, null: false

      t.timestamps
    end

    add_index :weekly_goals, [ :user_id, :week_start_date ]
  end
end
