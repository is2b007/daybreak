class CreateLogEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :log_entries do |t|
      t.references :daily_log, null: false, foreign_key: true
      t.text :content, null: false
      t.datetime :logged_at, null: false

      t.timestamps
    end
  end
end
