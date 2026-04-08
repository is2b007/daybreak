class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :name, null: false
      t.string :email
      t.string :timezone, default: "UTC", null: false
      t.string :stamp_choice, default: "red_done", null: false
      t.decimal :work_hours_target, default: 5.5, null: false
      t.string :sundown_time, default: "17:00", null: false
      t.string :theme, default: "system", null: false
      t.date :last_open_date
      t.string :basecamp_uid, null: false
      t.string :basecamp_access_token
      t.string :basecamp_refresh_token
      t.datetime :basecamp_token_expires_at
      t.string :basecamp_account_id
      t.string :hey_access_token
      t.string :hey_refresh_token
      t.datetime :hey_token_expires_at
      t.boolean :onboarded, default: false, null: false

      t.timestamps
    end

    add_index :users, :basecamp_uid, unique: true
  end
end
