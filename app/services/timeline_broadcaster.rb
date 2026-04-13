class TimelineBroadcaster
  def self.stream_name(user_id, date)
    d = date.is_a?(Date) ? date.iso8601 : date.to_s
    "timeline:user:#{user_id}:day:#{d}"
  end

  # Locals for `days/timeline` (hourly grid + positioned blocks).
  def self.timeline_locals(user, date)
    day_plan = user.day_plans.find_by(date: date)
    tasks = day_plan ? day_plan.task_assignments.ordered.to_a : []
    tz = user.timezone
    events = user.calendar_events.for_date(date).chronological.map { |e| e.to_timeline_hash(tz) }.compact.reject { |h| h[:all_day] }
    { date: date, events: events, tasks: tasks, timezone: tz }
  end

  def self.render_timeline(user, date)
    ApplicationController.render(
      partial: "days/timeline",
      locals: timeline_locals(user, date)
    )
  end

  def self.replace_for_day!(user, date, html: nil)
    return if Rails.env.test?

    html ||= render_timeline(user, date)
    Turbo::StreamsChannel.broadcast_replace_to(
      stream_name(user.id, date),
      target: "timeline_#{date}",
      html: html
    )
  end
end
