require "test_helper"

class WeeklyGoalsControllerTest < ActionController::TestCase
  setup do
    @user = users(:one)
    session[:user_id] = @user.id
    @goal = @user.weekly_goals.create!(title: "Ship v1", week_start_date: @user.current_week_start)
  end

  test "PATCH marks a goal done and back again" do
    patch :update, params: { id: @goal.id, completed: "1" }
    assert @goal.reload.completed

    patch :update, params: { id: @goal.id, completed: "0" }
    assert_not @goal.reload.completed
  end

  test "cannot touch another user's goal" do
    other = users(:two).weekly_goals.create!(title: "Theirs", week_start_date: @goal.week_start_date)
    assert_raises(ActiveRecord::RecordNotFound) do
      patch :update, params: { id: other.id, completed: "1" }
    end
    assert_not other.reload.completed
  end
end
