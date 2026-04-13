class AddLastPushedToHeyDigestToLocalJournalEntries < ActiveRecord::Migration[8.1]
  def change
    add_column :local_journal_entries, :last_pushed_to_hey_digest, :string
  end
end
