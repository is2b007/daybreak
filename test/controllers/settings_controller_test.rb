require "test_helper"

class SettingsControllerTest < ActionController::TestCase
  parallelize(workers: 1)

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

  test "show warns when HEY is connected without a refresh token" do
    @user.update!(
      hey_access_token: "pasted-token",
      hey_refresh_token: nil,
      hey_token_expires_at: 1.day.from_now
    )

    fake = Object.new
    fake.define_singleton_method(:calendars) { [] }
    original = HeyClient.method(:new)
    HeyClient.define_singleton_method(:new) { |_u| fake }

    get :show

    assert_response :success
    assert_match(/cannot refresh/, response.body)
    assert_match(/pasted CLI token/, response.body)
  ensure
    HeyClient.define_singleton_method(:new, original) if original
  end
end
