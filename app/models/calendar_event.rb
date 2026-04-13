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
      id: id,
      source: source,
      title: title,
      time: time_label,
      all_day: all_day,
      start_hour: start_hour,
      duration_hours: duration_hours,
      starts_at_iso: starts_at.iso8601,
      ends_at_iso: (ends_at || (starts_at + 1.hour)).iso8601
    }
  end

  # Attributes for the day timeline (positioned blocks). Returns nil when the event
  # does not overlap the rendered window (7am–after 9pm column).
  def to_timeline_hash(tz = user.timezone)
    px = TimelineLayout::PX_PER_HOUR
    h0 = TimelineLayout::HOUR_START
    h1 = TimelineLayout::HOUR_END + 1 # end of 9pm slot (22:00)

    base = { source: source, title: title, time: time_label, all_day: all_day }

    if all_day
      return base.merge(
        top_px: 2,
        height_px: (px / 2.0).round,
        id: id,
        external_id: external_id,
        hey_calendar_id: hey_calendar_id,
        starts_at_iso: starts_at.iso8601,
        ends_at_iso: (ends_at || starts_at.end_of_day).iso8601
      )
    end

    start_local = starts_at.in_time_zone(tz)
    end_local = (ends_at || (starts_at + 1.hour)).in_time_zone(tz)

    start_dec = start_local.hour + start_local.min / 60.0
    end_dec = end_local.hour + end_local.min / 60.0
    return nil if end_dec <= h0 || start_dec >= h1

    top_dec = [ [ start_dec, h0 ].max, h1 ].min
    bottom_dec = [ [ end_dec, h0 ].max, h1 ].min
    bottom_dec = [ bottom_dec, top_dec + 0.25 ].max

    top_px = ((top_dec - h0) * px).round
    height_px = [ ((bottom_dec - top_dec) * px).round, (px / 4.0).round ].max

    base.merge(
      top_px: top_px,
      height_px: height_px,
      id: id,
      external_id: external_id,
      hey_calendar_id: hey_calendar_id,
      starts_at_iso: starts_at.iso8601,
      ends_at_iso: (ends_at || (starts_at + 1.hour)).iso8601
    )
  end
end
