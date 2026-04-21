require "test_helper"

class SyncBasecampAssignmentsJobTest < ActiveJob::TestCase
  test "creates basecamp task_assignments from todo-shaped assignments" do
    user = users(:one)

    fake_class = Class.new do
      define_method(:initialize) { |_user| nil }
      define_method(:my_assignments) do
        [
          {
            "id" => 9_007_199_254_741_623,
            "type" => "todo",
            "content" => "Program the flux capacitor",
            "completed" => false,
            "description" => nil,
            "bucket" => { "id" => 2_085_958_504, "name" => "The Leto Laptop" }
          }
        ]
      end
    end

    assert_difference -> { TaskAssignment.where(user_id: user.id, source: :basecamp).count }, 1 do
      SyncBasecampAssignmentsJob.perform_now(user.id, basecamp_client_class: fake_class)
    end

    ta = TaskAssignment.where(user_id: user.id, source: :basecamp).last
    assert_equal "Program the flux capacitor", ta.title
    assert_equal "2085958504", ta.basecamp_bucket_id
    assert_equal "inbox", ta.week_bucket
  end

  test "User#current_week_start respects user timezone at 23:30 UTC on Sunday" do
    # 23:30 UTC on Sunday is already Monday in Tokyo (JST = UTC+9).
    user = users(:one)
    user.update!(timezone: "Asia/Tokyo")

    travel_to Time.utc(2026, 4, 19, 23, 30) do
      # Sunday in UTC, Monday 08:30 in Tokyo — new week has started for the user.
      assert_equal Date.new(2026, 4, 20), user.current_week_start
    end
  end
end
