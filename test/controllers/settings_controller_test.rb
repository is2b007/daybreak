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

  test "an explicit dark theme sets data-theme on html" do
    @user.update!(theme: "dark")
    get :show

    assert_select "html[data-theme=dark]"
    assert_select "select[name='user[theme]'] option[selected][value=dark]"
  end

  test "the system theme leaves data-theme off so the OS decides" do
    @user.update!(theme: "system")
    get :show

    assert_select "html[data-theme]", false
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

  test "show asks for a reconnect after HEY refused the connection" do
    @user.update!(hey_access_token: nil, hey_refresh_token: nil, hey_reconnect_needed_at: 1.hour.ago)

    get :show

    assert_response :success
    assert_match(/HEY stopped accepting Daybreak/, response.body)
    assert_match(/Reconnect HEY/, response.body)
  end
end
