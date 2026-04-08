class CalendarEvent < ApplicationRecord
  belongs_to :user

  enum :source, { basecamp: 0, hey: 1 }

  validates :external_id, :title, :starts_at, presence: true

  scope :for_date, ->(date) { where(starts_at: date.beginning_of_day..date.end_of_day) }
  scope :for_week, ->(week_start) {
    where(starts_at: week_start.beginning_of_day..(week_start + 6.days).end_of_day)
  }
  scope :chronological, -> { order(:starts_at) }

  def time_label
    return "All day" if all_day
    starts_at.in_time_zone(user.timezone).strftime("%-l:%M%P")
  end

  def start_hour
    starts_at.in_time_zone(user.timezone).hour
  end

  def duration_hours
    return 1 unless ends_at
    ((ends_at - starts_at) / 1.hour).ceil.clamp(1, 14)
  end

  def to_view_hash
    {
      source: source,
      title: title,
      time: time_label,
      start_hour: start_hour,
      duration_hours: duration_hours
    }
  end
end
