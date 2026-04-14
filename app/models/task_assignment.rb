class TaskAssignment < ApplicationRecord
  belongs_to :user
  belongs_to :day_plan, optional: true

  before_destroy :schedule_delete_hey_mirrored_todo
  before_destroy :destroy_daybreak_timebox_mirror

  enum :source, { local: 0, basecamp: 1, hey: 2 }
  enum :size, { small: 0, medium: 1, large: 2 }
  enum :status, { pending: 0, active: 1, completed: 2, deferred: 3 }

  validates :title, presence: true

  scope :ordered, -> { order(:position) }
  scope :for_week, ->(week_start) { where(week_start_date: week_start) }
  scope :sometime, -> { where(week_bucket: "sometime") }
  scope :for_day, -> { where(week_bucket: "day") }
  scope :incomplete, -> { where.not(status: :completed) }
  scope :timeboxed_for, ->(date) {
    where(planned_start_at: date.beginning_of_day..date.end_of_day)
  }

  def complete!(rotation: nil)
    update!(
      status: :completed,
      completed_at: Time.current,
      stamp_rotation_degrees: rotation || rand(-3..3)
    )
  end

  def cycle_size!
    next_size = case size
    when "small" then "medium"
    when "medium" then "large"
    when "large" then "small"
    end
    update!(size: next_size)
  end

  def defer_to_tomorrow!
    tomorrow_plan = user.day_plans.find_or_create_by!(date: Date.tomorrow)
    update!(day_plan: tomorrow_plan, status: :pending)
  end

  def defer_to_sometime!
    ws = Date.current.beginning_of_week(:monday)
    update!(day_plan: nil, week_bucket: "sometime", week_start_date: ws, status: :deferred)
  end

  def source_badge_color
    case source
    when "basecamp" then "var(--color-basecamp)"
    when "hey" then "var(--color-hey)"
    else nil
    end
  end

  def card_height_class
    "card--#{size}"
  end

  def timeboxed?
    planned_start_at.present?
  end

  def start_hour_in(timezone)
    return nil unless timeboxed?
    t = planned_start_at.in_time_zone(timezone)
    t.hour + (t.min / 60.0)
  end

  def duration_hours
    (planned_duration_minutes || 60) / 60.0
  end

  def schedule_delete_hey_mirrored_todo
    return if hey_mirrored_todo_id.blank?
    return unless user&.hey_connected?

    DeleteHeyMirroredTodoJob.perform_later(user_id, hey_mirrored_todo_id)
  end

  def destroy_daybreak_timebox_mirror
    return unless user_id

    CalendarEvent.destroy_daybreak_timebox_mirror!(user, id)
  end

  # Returns hey_app_url only if it uses a safe scheme (http/https).
  def safe_hey_app_url
    hey_app_url if hey_app_url&.match?(%r{\Ahttps?://}i)
  end

  # Web app URL for this todo (API ids match the web UI).
  def basecamp_web_url
    return nil unless basecamp?
    return nil if user&.basecamp_account_id.blank?
    return nil if basecamp_bucket_id.blank? || external_id.blank?

    "https://3.basecamp.com/#{user.basecamp_account_id}/buckets/#{basecamp_bucket_id}/todos/#{external_id}"
  end
end
