class AddForTriageIndexToHeyEmails < ActiveRecord::Migration[8.0]
  def change
    add_index :hey_emails, [:user_id, :received_at],
      where: "dismissed_at IS NULL AND triaged_at IS NULL",
      order: { received_at: :desc },
      name: "idx_hey_emails_for_triage"
  end
end
