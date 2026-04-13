class CalendarEvent < ApplicationRecord
  belongs_to :user

  # daybreak = timed block mirrored in Daybreak only when HEY OAuth cannot create a remote calendar event.
  enum :source, { basecamp: 0, hey: 1, daybreak: 2 }

  def self.daybreak_timebox_external_id(task_assignment_id)
    "daybreak-tbox-#{task_assignment_id}"
  end

  def self.destroy_daybreak_timebox_mirror!(user, task_assignment_id)
    user.calendar_events.find_by(
      external_id: daybreak_timebox_external_id(task_assignment_id),
      source: :daybreak
    )&.destroy!
  end

  def timeline_block?
    hey? || daybreak?
  end

  validates :external_id, :title, :starts_at, presence: true

  scope :for_date, ->(date) { where(starts_at: date.beginning_of_day..date.end_of_day) }
  # Daybreak = local timebox mirror only; it already renders on the hourly timeline, not the chip row.
  scope :for_day_chip_strip, -> { where.not(source: :daybreak) }

  # Top chip row: hide redundant HEY all-day pills when a timed HEY/daybreak block exists with the same title.
  def self.day_view_chip_records(user, date)
    day = user.calendar_events.for_date(date).for_day_chip_strip.chronological.to_a
    timed_titles = user.calendar_events.for_date(date).where(all_day: false, source: [ :hey, :daybreak ]).map { |e| e.title.to_s.strip.downcase }.to_set
    day.reject { |e| e.all_day && e.hey? && timed_titles.include?(e.title.to_s.strip.downcase) }
  end
  scope :for_week, ->(week_start) {
    where(starts_at: week_start.beginning_of_day..(week_start + 6.days).end_of_day)
  }
  scope :chronological, -> { order(:starts_at) }
  scope :pinned_to_week_board, -> { where(show_on_week_board: true) }

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
      external_id: external_id,
      starts_at_iso: starts_at.iso8601,
      ends_at_iso: (ends_at || (starts_at + 1.hour)).iso8601
    }
  end

  # Attributes for the day timeline (positioned blocks). Returns nil when the event
  # does not overlap the rendered window (7am–after 9pm column).
  # Positions use hours × var(--timeline-hour) so the grid can stretch with the column.
  def to_timeline_hash(tz = user.timezone)
    h0 = TimelineLayout::HOUR_START
    h1 = TimelineLayout::HOUR_END + 1 # end of 9pm slot (22:00)

    completed_flag = hey? && completed_at.present?
    base = { source: source, title: title, time: time_label, all_day: all_day, completed: completed_flag }

    if all_day
      return base.merge(
        id: id,
        external_id: external_id,
        hey_calendar_id: hey_calendar_id,
        source: source,
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

    top_offset_hours = (top_dec - h0).round(4)
    height_hours = [ (bottom_dec - top_dec).round(4), 0.25 ].max

    dur_mins = if ends_at
      ((ends_at - starts_at) / 1.minute).round.clamp(1, 24 * 60)
    else
      60
    end

    base.merge(
      top_offset_hours: top_offset_hours,
      height_hours: height_hours,
      duration_label: TimelineLayout.format_duration_hm(dur_mins),
      id: id,
      external_id: external_id,
      hey_calendar_id: hey_calendar_id,
      source: source,
      starts_at_iso: starts_at.iso8601,
      ends_at_iso: (ends_at || (starts_at + 1.hour)).iso8601
    )
  end
end
