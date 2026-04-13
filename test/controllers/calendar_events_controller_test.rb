require "test_helper"

class CalendarEventsControllerTest < ActionController::TestCase
  # HeyClient.new is stubbed at the class level; avoid parallel workers touching it concurrently.
  parallelize(workers: 1)

  FakeHey = Struct.new(:user) do
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

  test "PATCH update returns 422 when no HEY calendar id is known" do
    @hey_event.update_column(:hey_calendar_id, nil)
    @user.update_column(:hey_default_calendar_id, nil)

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

  test "DELETE destroys local event and calls HEY delete" do
    delete :destroy, params: { id: @hey_event.id }, as: :json

    assert_response :no_content
    assert_equal "cal-9", @hey_fake.deletes.last[:calendar_id]
    assert_raises(ActiveRecord::RecordNotFound) { @hey_event.reload }
  end
end
