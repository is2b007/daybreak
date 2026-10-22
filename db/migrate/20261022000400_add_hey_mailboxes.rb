class AddHeyMailboxes < ActiveRecord::Migration[8.1]
  # One HEY identity can hold several accounts (a personal mailbox plus work
  # domains). Boxes mix them together; each posting carries its account_id.
  def change
    add_column :hey_emails, :hey_account_id, :bigint
    add_index :hey_emails, [ :user_id, :hey_account_id ]
    add_column :users, :hey_accounts, :json
  end
end
