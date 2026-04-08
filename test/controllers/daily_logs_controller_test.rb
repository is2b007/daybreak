require "test_helper"

class DailyLogsControllerTest < ActionController::TestCase
  setup do
    @user = users(:one)
    session[:user_id] = @user.id
  end

  test "POST create reads :date param (regression for day_date typo)" do
    post :create, params: { date: "2026-04-08", content: "hello" }

    assert_redirected_to day_path("2026-04-08", tab: "log")
    log = @user.daily_logs.find_by(date: Date.parse("2026-04-08"))
    assert_not_nil log
    assert_equal 1, log.log_entries.count
    assert_equal "hello", log.log_entries.first.content
  end
end
