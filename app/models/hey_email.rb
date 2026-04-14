class HeyEmail < ApplicationRecord
  belongs_to :user

  enum :folder, { imbox: 0, reply_later: 1, set_aside: 2, feed: 3, paper_trail: 4 }

  validates :external_id, :subject, :received_at, presence: true

  scope :active, -> { where(dismissed_at: nil, triaged_at: nil) }
  scope :ordered, -> { order(received_at: :desc) }
  scope :for_triage, -> { active.ordered }
  scope :for_folder, ->(f) { where(folder: f) }

  def dismiss!
    update!(dismissed_at: Time.current)
  end

  def triage!
    update!(triaged_at: Time.current)
  end

  def handled?
    dismissed_at.present? || triaged_at.present?
  end

  # Returns hey_url only if it uses a safe scheme (http/https).
  def safe_hey_url
    hey_url if hey_url&.match?(%r{\Ahttps?://}i)
  end
end
