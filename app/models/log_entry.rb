class LogEntry < ApplicationRecord
  belongs_to :daily_log

  validates :content, presence: true
  validates :logged_at, presence: true
end
