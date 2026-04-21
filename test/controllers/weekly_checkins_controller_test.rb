require "test_helper"

class WeeklyCheckinsControllerTest < ActionController::TestCase
  setup do
    @user = users(:one)
    session[:user_id] = @user.id
    @week_start = @user.current_week_start
  end

  test "PATCH step 2 double-submit creates exactly 4 goals, not 8" do
    titles = [ "Ship v1", "Close Q2 review", "", "Rest" ]

    patch :update, params: { step: 2, goals: titles }
    patch :update, params: { step: 2, goals: titles }

    goals = @user.weekly_goals.where(week_start_date: @week_start).order(:position)
    assert_equal 3, goals.size, "blank titles should not produce goals; non-blank goals should be idempotent"
    assert_equal [ "Ship v1", "Close Q2 review", "Rest" ], goals.pluck(:title)
    assert_equal [ 0, 1, 2 ], goals.pluck(:position)
  end

  test "PATCH step 2 shrinks: going from 4 goals to 2 removes the extras" do
    patch :update, params: { step: 2, goals: [ "A", "B", "C", "D" ] }
    assert_equal 4, @user.weekly_goals.where(week_start_date: @week_start).count

    patch :update, params: { step: 2, goals: [ "A2", "B2" ] }
    titles = @user.weekly_goals.where(week_start_date: @week_start).order(:position).pluck(:title)
    assert_equal [ "A2", "B2" ], titles
  end
end
