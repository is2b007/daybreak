require "test_helper"

class TaskAssignmentTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @plan = @user.day_plans.create!(date: Date.parse("2026-04-07"))
  end

  test "reposition_to! renumbers the list contiguously" do
    a, b, c = %w[A B C].each_with_index.map { |title, i| day_task(title, i) }

    c.reposition_to!(0)

    assert_equal %w[C A B], @plan.task_assignments.ordered.pluck(:title)
    assert_equal [ 0, 1, 2 ], @plan.task_assignments.ordered.pluck(:position)
    assert_equal [ a, b ], [ a.reload, b.reload ]
  end

  test "reposition_to! clamps an index past the end of the list" do
    a = day_task("A", 0)
    day_task("B", 1)

    a.reposition_to!(99)

    assert_equal %w[B A], @plan.task_assignments.ordered.pluck(:title)
  end

  # Dropping onto an occupied index used to leave two cards sharing a position,
  # and the render order was then whatever the database returned.
  test "ordered breaks position ties deterministically by id" do
    first = day_task("first", 0)
    second = day_task("second", 0)

    assert_equal [ first.id, second.id ], @plan.task_assignments.ordered.pluck(:id)
  end

  test "sibling_scope for a sometime task is its week bucket, not its day plan" do
    task = @user.task_assignments.create!(
      title: "Someday", source: :local, week_bucket: "sometime",
      week_start_date: Date.parse("2026-04-06"), size: :medium, status: :pending, position: 0
    )

    assert_equal "sometime", task.sibling_scope.first.week_bucket
    assert_not_includes task.sibling_scope, day_task("A", 0)
  end

  test "defer_to_tomorrow! uses the owner's timezone" do
    @user.update!(timezone: "Pacific/Kiritimati") # UTC+14
    task = day_task("A", 0)

    travel_to Time.utc(2026, 4, 7, 23, 0) do
      task.defer_to_tomorrow!

      assert_equal @user.today_in_zone + 1.day, task.reload.day_plan.date
    end
  end

  private

  def day_task(title, position)
    @user.task_assignments.create!(
      day_plan: @plan, title: title, source: :local,
      week_start_date: Date.parse("2026-04-06"), week_bucket: "day",
      size: :medium, status: :pending, position: position
    )
  end
end
