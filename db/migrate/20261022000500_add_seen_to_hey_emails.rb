class AddSeenToHeyEmails < ActiveRecord::Migration[8.1]
  # HEY's box postings say whether the thread has been seen. Null means HEY
  # didn't say, which the panel shows as read rather than guess unread.
  def change
    add_column :hey_emails, :seen, :boolean
  end
end
