class CreateLocalJournalEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :local_journal_entries do |t|
      t.references :user, null: false, foreign_key: true
      t.date :date, null: false
      t.text :content, null: false

      t.timestamps
    end

    add_index :local_journal_entries, [ :user_id, :date ], unique: true
  end
end
