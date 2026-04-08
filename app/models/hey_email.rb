class HeyEmail < ApplicationRecord
  belongs_to :user

  enum :folder, { imbox: 0, reply_later: 1, set_aside: 2 }

  validates :external_id, :subject, :received_at, presence: true

  scope :active, -> { where(dismissed_at: nil, triaged_at: nil) }
  scope :ordered, -> { order(received_at: :desc) }
  scope :for_triage, -> { active.ordered }

  def dismiss!
    update!(dismissed_at: Time.current)
  end

  def triage!
    update!(triaged_at: Time.current)
  end

  def handled?
    dismissed_at.present? || triaged_at.present?
  end
end
