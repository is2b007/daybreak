class DailyLog < ApplicationRecord
  belongs_to :user
  has_many :log_entries, dependent: :destroy

  validates :date, presence: true, uniqueness: { scope: :user_id }

  scope :for_date, ->(date) { where(date: date) }

  def formatted_content
    log_entries.order(:logged_at).map do |entry|
      "#{entry.logged_at.strftime('%-I:%M%P')}\n#{entry.content}"
    end.join("\n\n")
  end
end
