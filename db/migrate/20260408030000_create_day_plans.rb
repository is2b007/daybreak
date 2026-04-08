class CreateDayPlans < ActiveRecord::Migration[8.1]
  def change
    create_table :day_plans do |t|
      t.references :user, null: false, foreign_key: true
      t.date :date, null: false
      t.integer :status, default: 0, null: false
      t.boolean :morning_ritual_done, default: false, null: false
      t.boolean :evening_ritual_done, default: false, null: false

      t.timestamps
    end

    add_index :day_plans, [ :user_id, :date ], unique: true
  end
end
