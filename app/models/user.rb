class User < ApplicationRecord
  encrypts :basecamp_access_token, :basecamp_refresh_token
  encrypts :hey_access_token, :hey_refresh_token

  has_many :day_plans, dependent: :destroy
  has_many :task_assignments, dependent: :destroy
  has_many :local_tasks, dependent: :destroy
  has_many :daily_logs, dependent: :destroy
  has_many :weekly_goals, dependent: :destroy
  has_many :local_journal_entries, dependent: :destroy
  has_many :local_timer_sessions, dependent: :destroy
  has_many :calendar_events, dependent: :destroy

  validates :name, presence: true
  validates :basecamp_uid, presence: true, uniqueness: true
  validates :timezone, presence: true
  validates :stamp_choice, inclusion: { in: %w[red_done navy_star green_check brown_complete black_dot] }
  validates :theme, inclusion: { in: %w[system light dark] }
  validates :work_hours_target, numericality: { greater_than: 0, less_than_or_equal_to: 24 }

  STAMP_OPTIONS = %w[red_done navy_star green_check brown_complete black_dot].freeze

  def hey_connected?
    hey_access_token.present?
  end

  def basecamp_token_fresh?
    basecamp_token_expires_at.present? && basecamp_token_expires_at > Time.current
  end

  def greeting_name
    name.split.first
  end

  def time_of_day_greeting
    hour = Time.current.in_time_zone(timezone).hour
    if hour < 12
      "Good morning"
    elsif hour < 17
      "Good afternoon"
    else
      "Good evening"
    end
  end

  def first_open_today?
    last_open_date != Date.current
  end

  def record_open!
    update_column(:last_open_date, Date.current)
  end
end
