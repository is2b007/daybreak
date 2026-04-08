require "test_helper"

class HeyEmailsControllerTest < ActionController::TestCase
  setup do
    @user = users(:one)
    @user.update!(
      hey_access_token: "stub-token",
      hey_refresh_token: "stub-refresh",
      hey_token_expires_at: 2.weeks.from_now
    )
    session[:user_id] = @user.id

    @email = @user.hey_emails.create!(
      external_id: "101",
      folder: :imbox,
      subject: "Ship the thing",
      snippet: "Can we wrap this up?",
      sender_name: "Alice",
      sender_email: "alice@example.com",
      received_at: 1.hour.ago,
      hey_url: "https://app.hey.com/topics/101"
    )
  end

  test "PATCH triage creates a local sometime task and stamps triaged_at" do
    assert_difference -> { @user.task_assignments.count }, 1 do
      patch :triage, params: { id: @email.id }, format: :turbo_stream
    end

    assert_response :success
    assert_not_nil @email.reload.triaged_at

    task = @user.task_assignments.order(:created_at).last
    assert_equal "local", task.source
    assert_equal "sometime", task.week_bucket
    assert_equal "Ship the thing", task.title
    assert_equal Date.current.beginning_of_week(:monday), task.week_start_date
  end

  test "PATCH triage responds with a turbo stream removing the row" do
    patch :triage, params: { id: @email.id }, format: :turbo_stream

    assert_response :success
    assert_match(/turbo-stream action="remove"/, @response.body)
    assert_match(/hey_email_#{@email.id}/, @response.body)
  end

  test "PATCH dismiss stamps dismissed_at and creates no task" do
    assert_no_difference -> { @user.task_assignments.count } do
      patch :dismiss, params: { id: @email.id }, format: :turbo_stream
    end

    assert_response :success
    assert_not_nil @email.reload.dismissed_at
    assert_nil @email.reload.triaged_at
  end

  test "PATCH dismiss responds with a turbo stream removing the row" do
    patch :dismiss, params: { id: @email.id }, format: :turbo_stream

    assert_response :success
    assert_match(/turbo-stream action="remove"/, @response.body)
    assert_match(/hey_email_#{@email.id}/, @response.body)
  end

  test "handles sync-race: acting on a row that was just pruned" do
    missing_id = @email.id
    @email.destroy!

    assert_no_difference -> { @user.task_assignments.count } do
      patch :triage, params: { id: missing_id }, format: :turbo_stream
    end

    # RecordNotFound is rescued and we still return a turbo-stream remove so
    # the UI sweeps the ghost row — don't leave a dead button on screen.
    assert_response :success
    assert_match(/turbo-stream action="remove"/, @response.body)
    assert_match(/hey_email_#{missing_id}/, @response.body)
  end

  test "cannot triage another user's email" do
    other = users(:two)
    other_email = other.hey_emails.create!(
      external_id: "999",
      folder: :imbox,
      subject: "Not yours",
      received_at: 1.hour.ago
    )

    assert_no_difference -> { @user.task_assignments.count } do
      patch :triage, params: { id: other_email.id }, format: :turbo_stream
    end

    # Scoped lookup treats cross-user access the same as sync-race: turbo-stream
    # remove targeting the requested id. The other user's row is untouched.
    assert_response :success
    assert_match(/turbo-stream action="remove"/, @response.body)
    assert_nil other_email.reload.triaged_at
  end
end
