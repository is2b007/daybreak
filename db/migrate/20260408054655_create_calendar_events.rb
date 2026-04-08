class CreateCalendarEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :calendar_events do |t|
      t.references :user, null: false, foreign_key: true
      t.string :external_id, null: false
      t.integer :source, null: false
      t.string :title, null: false
      t.datetime :starts_at, null: false
      t.datetime :ends_at
      t.boolean :all_day, default: false, null: false
      t.string :location
      t.text :description
      t.string :basecamp_bucket_id
      t.timestamps
    end

    add_index :calendar_events, [ :user_id, :starts_at ]
    add_index :calendar_events, [ :external_id, :source ], unique: true
  end
end
