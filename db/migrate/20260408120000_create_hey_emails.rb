class CreateHeyEmails < ActiveRecord::Migration[8.1]
  def change
    create_table :hey_emails do |t|
      t.references :user, null: false, foreign_key: true
      t.string :external_id, null: false
      t.integer :folder, null: false
      t.string :sender_name
      t.string :sender_email
      t.string :subject, null: false
      t.text :snippet
      t.datetime :received_at, null: false
      t.string :hey_url
      t.datetime :dismissed_at
      t.datetime :triaged_at
      t.timestamps
    end

    add_index :hey_emails, [ :user_id, :folder ]
    add_index :hey_emails, [ :user_id, :external_id ], unique: true
    add_index :hey_emails, [ :user_id, :received_at ]
  end
end
