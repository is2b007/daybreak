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
  has_many :hey_emails, dependent: :destroy

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

  def hey_token_fresh?
    hey_token_expires_at.present? && hey_token_expires_at > Time.current
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
    last_open_date != today_in_zone
  end

  def record_open!
    update_column(:last_open_date, today_in_zone)
  end

  def sunset_already_played_today?
    last_sunset_played_date == today_in_zone
  end

  def record_sunset_played!
    update_column(:last_sunset_played_date, today_in_zone)
  end

  def today_in_zone
    Time.current.in_time_zone(timezone).to_date
  end

  # Single source of truth for "this week" anchored to the user's local timezone.
  # Jobs and controllers must route through this — Date.current.beginning_of_week
  # drifts into the wrong week across midnight-UTC boundaries in non-UTC zones.
  def current_week_start
    today_in_zone.beginning_of_week(:monday)
  end

  # Fetches avatar URL from GET /my/profile.json and stores it for the sidebar photo + proxy.
  def sync_basecamp_avatar_url_from_api!
    return if basecamp_account_id.blank?

    client = BasecampClient.new(self)
    profile = client.my_profile
    raw = User.extract_basecamp_avatar_url_from_profile(profile)
    url = self.class.normalize_stored_basecamp_avatar_url(raw, basecamp_account_id: basecamp_account_id)
    if url.blank? && profile.is_a?(Hash)
      Rails.logger.warn(
        "sync_basecamp_avatar_url_from_api: no avatar_url in my/profile (keys=#{profile.keys.join(',')})"
      )
    end
    return if url.blank?

    update_column(:basecamp_avatar_url, url) if basecamp_avatar_url != url
  rescue StandardError => e
    Rails.logger.warn("sync_basecamp_avatar_url_from_api: #{e.class}: #{e.message}")
  end

  def self.extract_basecamp_avatar_url_from_profile(profile)
    return nil unless profile.is_a?(Hash)

    profile["avatar_url"].presence ||
      profile[:avatar_url].presence ||
      profile.dig("person", "avatar_url").presence
  end

  # Expand relative URLs, force https — API shapes differ slightly between accounts.
  def self.normalize_stored_basecamp_avatar_url(url, basecamp_account_id:)
    s = url.to_s.strip
    return nil if s.blank?

    s = s.sub(/\Ahttp:\/\//i, "https://")
    if s.start_with?("/")
      aid = basecamp_account_id.to_s.presence
      return nil if aid.blank?

      s = "#{BasecampClient::BASE_API_URL}/#{aid}#{s}"
    end
    s
  end
end
