# Pixel grid for day timeline (keep in sync with .timeline CSS --timeline-hour).
module TimelineLayout
  PX_PER_HOUR = 52
  HOUR_START = 7
  HOUR_END = 21 # last labeled hour; timeline runs through 9pm
  SNAP_SECONDS = 15 * 60

  # Wall-clock time snapped to 15-minute steps in +timezone_name+.
  def self.snap_zoned_time_to_grid(time, timezone_name)
    tz = ActiveSupport::TimeZone[timezone_name] || Time.zone
    t = time.in_time_zone(tz)
    base = t.beginning_of_day
    secs = t.to_i - base.to_i
    bucket = (secs.to_f / SNAP_SECONDS).round * SNAP_SECONDS
    base + bucket
  end

  def self.snap_duration_minutes(minutes)
    m = minutes.to_i
    [ [ ((m / 15.0).round * 15), 15 ].max, 24 * 60 ].min
  end

  # e.g. 90 → "1h 30m", 60 → "1h", 45 → "45m"
  def self.format_duration_hm(total_minutes)
    m = total_minutes.to_i
    return "0m" if m <= 0

    h, r = m.divmod(60)
    parts = []
    parts << "#{h}h" if h.positive?
    parts << "#{r}m" if r.positive?
    parts << "0m" if parts.empty?
    parts.join(" ")
  end
end
