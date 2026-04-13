require "test_helper"

class SettingsControllerTest < ActionController::TestCase
  setup do
    @user = users(:one)
    session[:user_id] = @user.id
  end

  test "PATCH update persists hey_default_calendar_id" do
    patch :update, params: {
      user: {
        name: @user.name,
        stamp_choice: @user.stamp_choice,
        timezone: @user.timezone,
        work_hours_target: @user.work_hours_target,
        sundown_time: "17:00",
        theme: @user.theme,
        hey_default_calendar_id: "cal-abc"
      }
    }

    assert_redirected_to settings_path
    assert_equal "cal-abc", @user.reload.hey_default_calendar_id
  end
end
