require "test_helper"

class TimerSessionsControllerTest < ActionController::TestCase
  setup do
    @user = users(:one)
    session[:user_id] = @user.id
    @plan = @user.day_plans.create!(date: Date.parse("2026-04-07"))
    @task = @user.task_assignments.create!(
      day_plan: @plan, title: "Focus work", source: :local,
      week_start_date: Date.parse("2026-04-06"), week_bucket: "day",
      size: :medium, status: :pending, position: 0
    )
  end

  test "POST create stops any timer already running" do
    other = @user.local_timer_sessions.create!(started_at: 30.minutes.ago)

    post :create, params: { task_assignment_id: @task.id }

    assert_not_nil other.reload.ended_at
    assert_equal 1, @user.local_timer_sessions.running.count
    assert_equal @task.id, @user.local_timer_sessions.running.first.task_assignment_id
  end

  # Stopping twice used to push ended_at forward on each submit, inflating the
  # recorded duration for the task.
  test "PATCH update on an already-stopped timer leaves the duration alone" do
    timer = @user.local_timer_sessions.create!(
      task_assignment: @task, started_at: 60.minutes.ago, ended_at: 30.minutes.ago
    )
    original_ended_at = timer.ended_at

    patch :update, params: { id: timer.id }

    assert_in_delta original_ended_at.to_i, timer.reload.ended_at.to_i, 1
  end

  test "PATCH update records elapsed minutes on the task" do
    timer = @user.local_timer_sessions.create!(task_assignment: @task, started_at: 25.minutes.ago)

    patch :update, params: { id: timer.id }

    assert_not_nil timer.reload.ended_at
    assert_in_delta 25, @task.reload.actual_duration_minutes, 1
  end
end
