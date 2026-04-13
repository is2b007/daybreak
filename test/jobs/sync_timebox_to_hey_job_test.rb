require "test_helper"

class SyncTimeboxToHeyJobTest < ActiveJob::TestCase
  parallelize(workers: 1)

  FakeHey = Struct.new(:user) do
    def create_todo(title:, starts_at: nil, ends_at: nil)
      (@creates ||= []) << [ title, starts_at, ends_at ]
      { "calendar_todo" => { "id" => "new-todo-id" } }
    end

    def delete_todo(id)
      (@deletes ||= []) << id
    end

    def creates
      @creates ||= []
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
    @plan = @user.day_plans.create!(date: Date.parse("2026-04-13"))
    @task = @user.task_assignments.create!(
      day_plan: @plan,
      title: "Boxed",
      week_start_date: Date.parse("2026-04-06"),
      week_bucket: "day",
      position: 0,
      planned_start_at: Time.zone.parse("2026-04-13 14:00"),
      planned_duration_minutes: 60,
      hey_calendar_event_id: "old-todo-id"
    )

    @hey_fake = FakeHey.new(@user)
    fake = @hey_fake
    @orig_hey_new = HeyClient.method(:new)
    HeyClient.define_singleton_method(:new) { |_u| fake }
  end

  teardown do
    HeyClient.define_singleton_method(:new, @orig_hey_new)
  end

  test "creates HEY todo and deletes previous id when it changes" do
    SyncTimeboxToHeyJob.perform_now(@task.id)

    assert_includes @hey_fake.deletes, "old-todo-id"
    assert_equal "new-todo-id", @task.reload.hey_calendar_event_id
    assert_equal "Boxed", @hey_fake.creates.last[0]
  end

  test "no-op when task is not timeboxed" do
    @task.update!(planned_start_at: nil, hey_calendar_event_id: nil)

    SyncTimeboxToHeyJob.perform_now(@task.id)

    assert_empty @hey_fake.creates
  end
end
