require "test_helper"

class JournalControllerTest < ActionController::TestCase
  setup do
    @user = users(:one)
    session[:user_id] = @user.id
    @date = Date.new(2026, 4, 13)
  end

  test "hey_badge_status is 404 when HEY not connected" do
    @user.update!(hey_access_token: nil, hey_refresh_token: nil, hey_token_expires_at: nil)

    get :hey_badge_status, params: { date: @date.to_s }, format: :json

    assert_response :not_found
  end

  test "hey_badge_status returns idle when no journal entry" do
    @user.update!(
      hey_access_token: "stub",
      hey_refresh_token: "stub-r",
      hey_token_expires_at: 2.weeks.from_now
    )
    @user.local_journal_entries.where(date: @date).delete_all

    get :hey_badge_status, params: { date: @date.to_s }, format: :json

    assert_response :success
    assert_equal "idle", JSON.parse(response.body)["state"]
  end

  test "hey_badge_status returns synced when digest matches last push" do
    @user.update!(
      hey_access_token: "stub",
      hey_refresh_token: "stub-r",
      hey_token_expires_at: 2.weeks.from_now
    )
    entry = @user.local_journal_entries.create!(date: @date, content: "<p>Synced body</p>")
    d = entry.content_digest
    entry.update_column(:last_pushed_to_hey_digest, d)

    get :hey_badge_status, params: { date: @date.to_s }, format: :json

    assert_response :success
    assert_equal "synced", JSON.parse(response.body)["state"]
  end

  test "hey_badge_status returns pending when entry exists but digest mismatch" do
    @user.update!(
      hey_access_token: "stub",
      hey_refresh_token: "stub-r",
      hey_token_expires_at: 2.weeks.from_now
    )
    @user.local_journal_entries.create!(date: @date, content: "<p>Pending</p>")

    get :hey_badge_status, params: { date: @date.to_s }, format: :json

    assert_response :success
    assert_equal "pending", JSON.parse(response.body)["state"]
  end
end
