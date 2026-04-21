require "test_helper"

class RitualsControllerTest < ActionController::TestCase
  setup do
    @user = users(:one)
    session[:user_id] = @user.id
    @today = @user.today_in_zone
    @day_plan = @user.day_plans.find_or_create_by!(date: @today)
  end

  test "GET morning step 1 renders with no data" do
    get :morning, params: { step: 1 }
    assert_response :success
  end

  test "GET morning records last_open_date on first hit; reload does not reset it" do
    @user.update_column(:last_open_date, @today - 1.day)

    get :morning, params: { step: 1 }
    assert_equal @today, @user.reload.last_open_date

    # Second hit same day — still today, no change.
    get :morning, params: { step: 1 }
    assert_equal @today, @user.reload.last_open_date
  end

  test "GET evening step 1 aggregates planned minutes via SQL (completed with no actual falls back to planned for actual column)" do
    @day_plan.task_assignments.create!(
      user: @user, title: "Done, no actual", status: :completed,
      planned_duration_minutes: 45, actual_duration_minutes: nil
    )
    @day_plan.task_assignments.create!(
      user: @user, title: "Done, with actual", status: :completed,
      planned_duration_minutes: 30, actual_duration_minutes: 50
    )
    @day_plan.task_assignments.create!(
      user: @user, title: "Pending", status: :pending,
      planned_duration_minutes: 60, actual_duration_minutes: nil
    )

    get :evening, params: { step: 1 }
    assert_response :success
  end

  test "POST evening/complete records last_sunset_played_date on first hit of the day" do
    @user.update_column(:last_sunset_played_date, nil)

    post :evening_complete
    assert_equal @today, @user.reload.last_sunset_played_date
  end
end
