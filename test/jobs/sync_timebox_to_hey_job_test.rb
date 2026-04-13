require "test_helper"

class SyncTimeboxToHeyJobTest < ActiveJob::TestCase
  parallelize(workers: 1)

  FakeHey = Struct.new(:user) do
    def update_calendar_event(**kwargs)
      (@updates ||= []) << kwargs
      {}
    end

    def create_calendar_event(**kwargs)
      (@creates ||= []) << kwargs
      { "calendar_event" => { "id" => "new-cal-event-id" } }
    end

    def delete_calendar_event(**kwargs)
      (@cal_deletes ||= []) << kwargs
    end

    def delete_todo(id)
      (@todo_deletes ||= []) << id
    end

    def creates
      @creates ||= []
    end

    def updates
      @updates ||= []
    end

    def todo_deletes
      @todo_deletes ||= []
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
      hey_calendar_event_id: "old-remote-id"
    )

    @hey_fake = FakeHey.new(@user)
    fake = @hey_fake
    @orig_hey_new = HeyClient.method(:new)
    HeyClient.define_singleton_method(:new) { |_u| fake }
  end

  teardown do
    HeyClient.define_singleton_method(:new, @orig_hey_new)
  end

  test "updates existing HEY calendar event when id present" do
    SyncTimeboxToHeyJob.perform_now(@task.id)

    assert_equal 1, @hey_fake.updates.size
    assert_equal "old-remote-id", @hey_fake.updates.last[:event_id]
    assert_equal "cal-default", @hey_fake.updates.last[:calendar_id]
    assert_empty @hey_fake.creates
    assert_equal "old-remote-id", @task.reload.hey_calendar_event_id
  end

  test "creates calendar event when update returns nil (legacy cleanup then create)" do
    @hey_fake.define_singleton_method(:update_calendar_event) { |**_| nil }

    SyncTimeboxToHeyJob.perform_now(@task.id)

    assert_includes @hey_fake.todo_deletes, "old-remote-id"
    assert_equal 1, @hey_fake.creates.size
    assert_equal "new-cal-event-id", @task.reload.hey_calendar_event_id
  end

  test "no-op when task is not timeboxed" do
    @task.update!(planned_start_at: nil, hey_calendar_event_id: nil)

    SyncTimeboxToHeyJob.perform_now(@task.id)

    assert_empty @hey_fake.creates
    assert_empty @hey_fake.updates
  end

  test "skips when default calendar missing" do
    @user.update_column(:hey_default_calendar_id, nil)

    SyncTimeboxToHeyJob.perform_now(@task.id)

    assert_empty @hey_fake.creates
    assert_empty @hey_fake.updates
  end
end
