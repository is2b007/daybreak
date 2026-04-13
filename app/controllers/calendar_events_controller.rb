class CalendarEventsController < ApplicationController
  before_action :set_event

  # Drag calendar chip onto timeline: server computes wall time in the user timezone.
  def slot
    return head :forbidden unless @event.hey?

    date = Date.parse(params.require(:date))
    hour = params.require(:hour).to_i
    minute = params.require(:minute).to_i
    tz = ActiveSupport::TimeZone[current_user.timezone] || Time.zone
    starts = tz.local(date.year, date.month, date.day, hour, minute)
    ends = if @event.ends_at && @event.starts_at
      starts + (@event.ends_at - @event.starts_at)
    else
      starts + 1.hour
    end

    apply_hey_calendar_update!(starts: starts, ends: ends, title: @event.title)
  end

  def update
    return head :forbidden unless @event.hey?

    starts = Time.zone.parse(params.require(:starts_at))
    ends = if params[:ends_at].present?
      Time.zone.parse(params[:ends_at])
    elsif @event.ends_at
      starts + (@event.ends_at - @event.starts_at)
    else
      starts + 1.hour
    end

    title = params[:title].presence || @event.title

    apply_hey_calendar_update!(starts: starts, ends: ends, title: title)
  end

  def destroy
    return head :forbidden unless @event.hey?

    cid = @event.hey_calendar_id.presence || current_user.hey_default_calendar_id
    return head :unprocessable_entity if cid.blank?

    d = @event.starts_at.in_time_zone(current_user.timezone).to_date

    client = HeyClient.new(current_user)
    begin
      client.delete_calendar_event(calendar_id: cid, event_id: @event.external_id)
    rescue StandardError => e
      Rails.logger.warn("HEY calendar event remote delete failed: #{e.message}")
    end

    @event.destroy!
    broadcast_timeline_for(d)
    head :no_content
  rescue HeyClient::AuthError
    head :unauthorized
  end

  private

  def apply_hey_calendar_update!(starts:, ends:, title:)
    cid = @event.hey_calendar_id.presence || current_user.hey_default_calendar_id
    return head :unprocessable_entity if cid.blank?

    client = HeyClient.new(current_user)
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

    broadcast_timeline_for(starts.in_time_zone(current_user.timezone).to_date)
    head :no_content
  rescue HeyClient::AuthError
    head :unauthorized
  end

  def set_event
    @event = current_user.calendar_events.find(params[:id])
  end

  def broadcast_timeline_for(date)
    TimelineBroadcaster.replace_for_day!(current_user, date)
  end
end
