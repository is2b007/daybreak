require "test_helper"

class CalendarEventsControllerTest < ActionController::TestCase
  # HeyClient.new is stubbed at the class level; avoid parallel workers touching it concurrently.
  parallelize(workers: 1)

  FakeHey = Struct.new(:user) do
    def calendar_id_for_timed_writes
      user.hey_default_calendar_id.presence || instance_variable_get(:@__resolved_cal)
    end

    def force_resolved_calendar_id!(id)
      instance_variable_set(:@__resolved_cal, id)
    end

    def update_calendar_event(**kwargs)
      (@updates ||= []) << kwargs
      { "id" => kwargs[:event_id] }
    end

    def delete_calendar_event(**kwargs)
      (@deletes ||= []) << kwargs
    end

    def updates
      @updates ||= []
    end

    def deletes
      @deletes ||= []
    end
  end

  setup do
    @user = users(:one)
    @user.update!(
      hey_access_token: "stub",
      hey_refresh_token: "stub",
      hey_token_expires_at: 1.day.from_now
    )
    session[:user_id] = @user.id

    @hey_event = @user.calendar_events.create!(
      external_id: "hey-ev-1",
      source: :hey,
      title: "Meet",
      starts_at: Time.zone.parse("2026-04-13 14:00"),
      ends_at: Time.zone.parse("2026-04-13 15:00"),
      all_day: false,
      hey_calendar_id: "cal-9"
    )

    @hey_fake = FakeHey.new(@user)
    @hey_fake.force_resolved_calendar_id!("cal-personal")
    fake = @hey_fake
    @orig_hey_new = HeyClient.method(:new)
    HeyClient.define_singleton_method(:new) { |_u| fake }
  end

  teardown do
    HeyClient.define_singleton_method(:new, @orig_hey_new)
  end

  test "PATCH slot reschedules using date hour minute in user timezone" do
    patch :slot,
      params: {
        id: @hey_event.id,
        date: "2026-04-13",
        hour: "10",
        minute: "30"
      }

    assert_response :no_content
    assert_equal "hey-ev-1", @hey_fake.updates.last[:event_id]
    ev = @hey_event.reload
    assert_equal 10, ev.starts_at.in_time_zone(@user.timezone).hour
    assert_equal 30, ev.starts_at.in_time_zone(@user.timezone).min
  end

  test "PATCH update accepts wall minutes on day column date in user timezone" do
    patch :update,
      params: {
        id: @hey_event.id,
        date: "2026-04-13",
        start_minutes_from_midnight: 15 * 60,
        duration_minutes: 60
      },
      as: :json

    assert_response :no_content
    assert_equal 15, @hey_event.reload.starts_at.in_time_zone(@user.timezone).hour
    assert_equal 16, @hey_event.ends_at.in_time_zone(@user.timezone).hour
  end

  test "PATCH update syncs HEY and updates local times" do
    patch :update,
      params: {
        id: @hey_event.id,
        starts_at: "2026-04-13T15:00:00.000-07:00",
        ends_at: "2026-04-13T16:00:00.000-07:00"
      },
      as: :json

    assert_response :no_content
    assert_equal "cal-9", @hey_fake.updates.last[:calendar_id]
    assert_equal "hey-ev-1", @hey_fake.updates.last[:event_id]
    assert_equal 15, @hey_event.reload.starts_at.in_time_zone(@user.timezone).hour
  end

  test "PATCH update is forbidden for Basecamp-sourced events" do
    bc = @user.calendar_events.create!(
      external_id: "bc-1",
      source: :basecamp,
      title: "BC",
      starts_at: Time.zone.parse("2026-04-13 10:00"),
      ends_at: Time.zone.parse("2026-04-13 11:00"),
      all_day: false
    )

    patch :update,
      params: {
        id: bc.id,
        starts_at: "2026-04-13T11:00:00.000-07:00",
        ends_at: "2026-04-13T12:00:00.000-07:00"
      },
      as: :json

    assert_response :forbidden
    assert_empty @hey_fake.updates
  end

  test "PATCH update uses resolved calendar when event and default ids are blank" do
    @hey_event.update_column(:hey_calendar_id, nil)
    @user.update_column(:hey_default_calendar_id, nil)

    patch :update,
      params: {
        id: @hey_event.id,
        starts_at: "2026-04-13T15:00:00.000-07:00",
        ends_at: "2026-04-13T16:00:00.000-07:00"
      },
      as: :json

    assert_response :no_content
    assert_equal "cal-personal", @hey_fake.updates.last[:calendar_id]
    assert_equal "cal-personal", @hey_event.reload.hey_calendar_id
  end

  test "PATCH update returns 422 when resolver yields no calendar id" do
    @hey_event.update_column(:hey_calendar_id, nil)
    @user.update_column(:hey_default_calendar_id, nil)
    @hey_fake.force_resolved_calendar_id!(nil)

    patch :update,
      params: {
        id: @hey_event.id,
        starts_at: "2026-04-13T15:00:00.000-07:00",
        ends_at: "2026-04-13T16:00:00.000-07:00"
      },
      as: :json

    assert_response :unprocessable_entity
    assert_empty @hey_fake.updates
  end

  test "PATCH update with turbo_stream returns timeline replace" do
    patch :update,
      params: {
        id: @hey_event.id,
        starts_at: "2026-04-13T15:00:00.000-07:00",
        ends_at: "2026-04-13T16:00:00.000-07:00"
      },
      as: :turbo_stream

    assert_response :success
    assert_includes @response.body, "turbo-stream"
    assert_includes @response.body, "timeline_2026-04-13"
    assert_equal 15, @hey_event.reload.starts_at.in_time_zone(@user.timezone).hour
  end

  test "PATCH update on daybreak timebox mirror updates task times without HEY API" do
    plan = @user.day_plans.create!(date: Date.parse("2026-04-13"))
    task = @user.task_assignments.create!(
      day_plan: plan,
      title: "Local box",
      week_start_date: Date.parse("2026-04-06"),
      week_bucket: "day",
      position: 0,
      planned_start_at: Time.zone.parse("2026-04-13 14:00"),
      planned_duration_minutes: 60
    )
    ev = @user.calendar_events.create!(
      external_id: CalendarEvent.daybreak_timebox_external_id(task.id),
      source: :daybreak,
      title: task.title,
      starts_at: task.planned_start_at,
      ends_at: task.planned_start_at + 60.minutes,
      all_day: false
    )

    patch :update,
      params: {
        id: ev.id,
        starts_at: "2026-04-13T15:00:00.000-07:00",
        ends_at: "2026-04-13T16:00:00.000-07:00"
      },
      as: :json

    assert_response :no_content
    assert_empty @hey_fake.updates
    assert_equal 15, task.reload.planned_start_at.in_time_zone(@user.timezone).hour
    assert_equal 60, task.planned_duration_minutes
  end

  test "DELETE destroys local event and calls HEY delete" do
    delete :destroy, params: { id: @hey_event.id }, as: :json

    assert_response :no_content
    assert_equal "cal-9", @hey_fake.deletes.last[:calendar_id]
    assert_raises(ActiveRecord::RecordNotFound) { @hey_event.reload }
  end
end
