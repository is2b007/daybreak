require "test_helper"

class SyncTimeboxToHeyJobTest < ActiveJob::TestCase
  parallelize(workers: 1)

  FakeHey = Struct.new(:user, :remote_id) do
    def calendar_id_for_timed_writes
      "cal-default"
    end

    def delete_timebox_mirror_remote_id(id)
      (@mirror_deletes ||= []) << id
    end

    def create_timed_calendar_event_form(calendar_id:, title:, local_start:, local_end:, time_zone:)
      (@event_creates ||= []) << {
        calendar_id: calendar_id,
        title: title,
        local_start: local_start,
        local_end: local_end,
        time_zone: time_zone
      }
      remote_id
    end

    def event_creates
      @event_creates ||= []
    end

    def mirror_deletes
      @mirror_deletes ||= []
    end
  end

  setup do
    @user = users(:one)
    @user.update!(
      hey_access_token: "stub",
      hey_refresh_token: "stub",
      hey_token_expires_at: 1.day.from_now,
      hey_default_calendar_id: "cal-default"
    )
    @plan = @user.day_plans.create!(date: Date.parse("2026-04-13"))
    @task = @user.task_assignments.create!(
      day_plan: @plan,
      title: "Boxed",
      week_start_date: Date.parse("2026-04-06"),
      week_bucket: "day",
      position: 0,
      planned_start_at: Time.zone.parse("2026-04-13 14:00"),
      planned_duration_minutes: 60,
      hey_calendar_event_id: "old-event-id"
    )

    @hey_fake = FakeHey.new(@user, "event-remote-new")
    fake = @hey_fake
    @orig_hey_new = HeyClient.method(:new)
    HeyClient.define_singleton_method(:new) { |_u| fake }
  end

  teardown do
    HeyClient.define_singleton_method(:new, @orig_hey_new)
  end

  test "replaces existing HEY mirror by delete then create timed calendar event" do
    SyncTimeboxToHeyJob.perform_now(@task.id)

    assert_equal %w[old-event-id], @hey_fake.mirror_deletes
    assert_equal 1, @hey_fake.event_creates.size
    c = @hey_fake.event_creates.last
    assert_equal "cal-default", c[:calendar_id]
    assert_equal "Boxed", c[:title]
    assert_equal "America/Los_Angeles", c[:time_zone]
    assert_operator c[:local_end], :>, c[:local_start]
    assert_equal "event-remote-new", @task.reload.hey_calendar_event_id
    assert_not @user.calendar_events.exists?(source: :daybreak, external_id: CalendarEvent.daybreak_timebox_external_id(@task.id))
  end

  test "creates calendar event when no prior mirror id" do
    @task.update_column(:hey_calendar_event_id, nil)

    SyncTimeboxToHeyJob.perform_now(@task.id)

    assert_empty @hey_fake.mirror_deletes
    assert_equal 1, @hey_fake.event_creates.size
    assert_equal "event-remote-new", @task.reload.hey_calendar_event_id
  end

  test "persists daybreak calendar row when HEY API returns no remote id" do
    @hey_fake.remote_id = nil
    @task.update_column(:hey_calendar_event_id, nil)

    SyncTimeboxToHeyJob.perform_now(@task.id)

    assert_equal 1, @hey_fake.event_creates.size
    assert_nil @task.reload.hey_calendar_event_id
    ev = @user.calendar_events.find_by!(source: :daybreak, external_id: CalendarEvent.daybreak_timebox_external_id(@task.id))
    assert_equal "Boxed", ev.title
    assert_not ev.all_day
  end

  test "no-op when task is not timeboxed" do
    @task.update!(planned_start_at: nil, hey_calendar_event_id: nil)

    SyncTimeboxToHeyJob.perform_now(@task.id)

    assert_empty @hey_fake.event_creates
    assert_empty @hey_fake.mirror_deletes
  end

  test "creates daybreak mirror when HEY calendar id cannot be resolved" do
    @hey_fake.define_singleton_method(:calendar_id_for_timed_writes) { nil }
    @task.update_column(:hey_calendar_event_id, nil)

    SyncTimeboxToHeyJob.perform_now(@task.id)

    assert_empty @hey_fake.event_creates
    assert @user.calendar_events.exists?(source: :daybreak, external_id: CalendarEvent.daybreak_timebox_external_id(@task.id))
  end
end
