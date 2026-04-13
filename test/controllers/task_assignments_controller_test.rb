require "test_helper"

class TaskAssignmentsControllerTest < ActionController::TestCase
  setup do
    @user = users(:one)
    session[:user_id] = @user.id

    @source_plan = @user.day_plans.create!(date: Date.parse("2026-04-07"))
    @task = @user.task_assignments.create!(
      day_plan: @source_plan,
      title: "Ship spec 01",
      week_start_date: Date.parse("2026-04-06"),
      week_bucket: "day",
      position: 0
    )
  end

  test "PATCH restore_hey_email clears triage and destroys task" do
    email = @user.hey_emails.create!(
      external_id: "restore-1",
      folder: :imbox,
      subject: "Restorable",
      received_at: 1.hour.ago,
      hey_url: "https://app.hey.com/topics/restore-1",
      triaged_at: Time.current
    )
    task = @user.task_assignments.create!(
      day_plan: @source_plan,
      title: "Restorable",
      hey_app_url: email.hey_url,
      week_start_date: Date.parse("2026-04-06"),
      week_bucket: "day",
      position: 0,
      source: :local,
      size: :medium,
      status: :pending
    )
    patch :restore_hey_email, params: { id: task.id }, format: :turbo_stream
    assert_response :success
    assert_nil email.reload.triaged_at
    assert_raises(ActiveRecord::RecordNotFound) { task.reload }
  end

  test "PATCH move renders turbo stream (regression for missing template)" do
    patch :move,
      params: { id: @task.id, target_date: "2026-04-09", position: 0, source_date: "2026-04-07" },
      format: :turbo_stream

    assert_response :success
    assert_equal Date.parse("2026-04-09"), @task.reload.day_plan.date
    assert_match(/day_2026-04-09/, @response.body)
    assert_match(/day_2026-04-07/, @response.body)
  end
end
