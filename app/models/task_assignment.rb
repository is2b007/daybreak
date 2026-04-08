class TaskAssignment < ApplicationRecord
  belongs_to :user
  belongs_to :day_plan, optional: true

  enum :source, { local: 0, basecamp: 1, hey: 2 }
  enum :size, { small: 0, medium: 1, large: 2 }
  enum :status, { pending: 0, active: 1, completed: 2, deferred: 3 }

  validates :title, presence: true

  scope :ordered, -> { order(:position) }
  scope :for_week, ->(week_start) { where(week_start_date: week_start) }
  scope :sometime, -> { where(week_bucket: "sometime") }
  scope :for_day, -> { where(week_bucket: "day") }
  scope :incomplete, -> { where.not(status: :completed) }

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
    update!(day_plan: nil, week_bucket: "sometime", status: :deferred)
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
end
