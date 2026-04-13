class CalendarEventsController < ApplicationController
  before_action :set_event

  # Drag calendar chip onto timeline: server computes wall time in the user timezone.
  def slot
    return head :forbidden unless timeline_editable_event?

    date = Date.parse(params.require(:date))
    hour = params.require(:hour).to_i
    minute = params.require(:minute).to_i
    tz = user_tz
    starts = tz.local(date.year, date.month, date.day, hour, minute)
    ends = if @event.ends_at && @event.starts_at
      starts + (@event.ends_at - @event.starts_at)
    else
      starts + 1.hour
    end

    apply_calendar_update!(starts: starts, ends: ends, title: @event.title)
  end

  def update
    return head :forbidden unless timeline_editable_event?

    tz = user_tz
    parsed = parse_timeline_drag_times(tz)
    return head :unprocessable_entity if parsed.nil?

    starts, ends = parsed
    title = params[:title].presence || @event.title

    apply_calendar_update!(starts: starts, ends: ends, title: title)
  end

  def destroy
    return head :forbidden unless timeline_editable_event?

    d = @event.starts_at.in_time_zone(current_user.timezone).to_date

    if @event.hey?
      client = HeyClient.new(current_user)
      cid = @event.hey_calendar_id.presence || client.calendar_id_for_timed_writes
      return head :unprocessable_entity if cid.blank?

      begin
        client.delete_calendar_event(calendar_id: cid, event_id: @event.external_id)
      rescue StandardError => e
        Rails.logger.warn("HEY calendar event remote delete failed: #{e.message}")
      end
    end

    clear_linked_task_timebox! if @event.daybreak?

    @event.destroy!
    respond_timeline_success(d)
  rescue HeyClient::AuthError
    head :unauthorized
  end

  private

  def user_tz
    ActiveSupport::TimeZone[current_user.timezone] || Time.zone
  end

  # Timeline drag sends wall clock in the *day column date* using the user's IANA zone
  # (avoids browser-local Date + ISO UTC vs server TZ mismatches that drop blocks from the strip).
  def parse_timeline_drag_times(tz)
    pm = params[:start_minutes_from_midnight]
    dm = params[:duration_minutes]
    if params[:date].present? && !pm.nil? && !dm.nil?
      date = Date.parse(params.require(:date))
      sm = pm.to_i
      dur = dm.to_i
      dur = TimelineLayout.snap_duration_minutes(dur)
      sm = sm.clamp(0, (24 * 60) - 15)
      starts = tz.local(date.year, date.month, date.day, sm / 60, sm % 60)
      ends = starts + dur.minutes
      return [ starts, ends ]
    end

    return nil unless params[:starts_at].present?

    starts = tz.parse(params.require(:starts_at))
    ends = if params[:ends_at].present?
      tz.parse(params[:ends_at])
    elsif @event.ends_at
      starts + (@event.ends_at - @event.starts_at)
    else
      starts + 1.hour
    end
    [ starts, ends ]
  end

  def respond_timeline_success(date)
    html = TimelineBroadcaster.render_timeline(current_user, date)
    TimelineBroadcaster.replace_for_day!(current_user, date, html: html)
    if request.format.turbo_stream?
      render turbo_stream: turbo_stream.replace("timeline_#{date}", html: html)
    else
      head :no_content
    end
  end

  def timeline_editable_event?
    @event.hey? || @event.daybreak?
  end

  def apply_calendar_update!(starts:, ends:, title:)
    starts = TimelineLayout.snap_zoned_time_to_grid(starts, current_user.timezone)
    ends = TimelineLayout.snap_zoned_time_to_grid(ends, current_user.timezone)
    ends = starts + 15.minutes if ends <= starts

    if @event.daybreak?
      @event.update!(
        title: title,
        starts_at: starts,
        ends_at: ends,
        all_day: false
      )
      sync_daybreak_timebox_task!(starts, ends)
      respond_timeline_success(starts.in_time_zone(current_user.timezone).to_date)
      return
    end

    client = HeyClient.new(current_user)
    cid = @event.hey_calendar_id.presence || client.calendar_id_for_timed_writes
    return head :unprocessable_entity if cid.blank?

    result = client.update_calendar_event(
      calendar_id: cid,
      event_id: @event.external_id,
      title: title,
      starts_at: starts,
      ends_at: ends,
      all_day: @event.all_day
    )

    if result.nil?
      head :unprocessable_entity
      return
    end

    @event.update!(
      title: title,
      starts_at: starts,
      ends_at: ends,
      all_day: @event.all_day
    )
    @event.update_column(:hey_calendar_id, cid) if @event.hey_calendar_id.blank?

    respond_timeline_success(starts.in_time_zone(current_user.timezone).to_date)
  rescue HeyClient::AuthError
    head :unauthorized
  end

  def sync_daybreak_timebox_task!(starts, ends)
    tid = daybreak_task_assignment_id
    return unless tid

    task = current_user.task_assignments.find_by(id: tid)
    return unless task

    mins = [ ((ends - starts) / 60.0).round, 15 ].max
    task.update!(planned_start_at: starts, planned_duration_minutes: mins, hey_calendar_event_id: nil)
  end

  def clear_linked_task_timebox!
    tid = daybreak_task_assignment_id
    return unless tid

    current_user.task_assignments.find_by(id: tid)&.update!(planned_start_at: nil, hey_calendar_event_id: nil)
  end

  def daybreak_task_assignment_id
    m = @event.external_id.to_s.match(/\Adaybreak-tbox-(\d+)\z/)
    m ? m[1].to_i : nil
  end

  def set_event
    @event = current_user.calendar_events.find(params[:id])
  end

end
