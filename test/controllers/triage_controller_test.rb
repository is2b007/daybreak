require "test_helper"

class TriageControllerTest < ActionController::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = users(:one)
    session[:user_id] = @user.id
  end

  test "redirects to root when HEY is not connected" do
    @user.update!(hey_access_token: nil, hey_refresh_token: nil, hey_token_expires_at: nil)

    get :show

    assert_redirected_to root_path
    assert_match(/Connect HEY/i, flash[:alert])
  end

  test "renders and groups emails by folder when HEY is connected" do
    @user.update!(
      hey_access_token: "stub-token",
      hey_refresh_token: "stub-refresh",
      hey_token_expires_at: 2.weeks.from_now
    )
    @user.hey_emails.create!(
      external_id: "1", folder: :imbox, subject: "Imbox one subject", received_at: 1.hour.ago
    )
    @user.hey_emails.create!(
      external_id: "2", folder: :reply_later, subject: "Later one subject", received_at: 2.hours.ago
    )
    # A triaged row should NOT appear in the rendered page — for_triage filters it out.
    @user.hey_emails.create!(
      external_id: "3", folder: :imbox, subject: "Already handled subject", received_at: 30.minutes.ago,
      triaged_at: 5.minutes.ago
    )

    get :show

    assert_response :success
    assert_match(/Imbox one subject/, @response.body)
    assert_match(/Later one subject/, @response.body)
    assert_no_match(/Already handled subject/, @response.body)
  end

  test "enqueues SyncHeyEmailsJob for on-demand refresh" do
    @user.update!(
      hey_access_token: "stub-token",
      hey_refresh_token: "stub-refresh",
      hey_token_expires_at: 2.weeks.from_now
    )

    assert_enqueued_with(job: SyncHeyEmailsJob, args: [ @user.id ]) do
      get :show
    end
  end
end
