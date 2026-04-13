require "test_helper"

class SyncInboxSometimeTodoToHeyJobTest < ActiveJob::TestCase
  parallelize(workers: 1)

  setup do
    @user = users(:one)
    @user.update!(
      hey_access_token: "stub",
      hey_refresh_token: "stub-r",
      hey_token_expires_at: 2.weeks.from_now
    )
    week_start = Date.new(2026, 4, 13).beginning_of_week(:monday)
    @task = @user.task_assignments.create!(
      source: :local,
      title: "From inbox",
      hey_app_url: "https://app.hey.com/threads/1",
      week_start_date: week_start,
      week_bucket: "sometime",
      size: :medium,
      status: :pending,
      position: 0
    )
  end

  def with_hey_client(client)
    original = HeyClient.method(:new)
    HeyClient.define_singleton_method(:new) { |_u| client }
    yield
  ensure
    HeyClient.define_singleton_method(:new, original)
  end

  test "creates HEY todo and stores mirrored id" do
    client = Object.new
    client.define_singleton_method(:create_todo) do |**_|
      { "calendar_todo" => { "id" => "todo-remote-1" } }
    end

    with_hey_client(client) do
      SyncInboxSometimeTodoToHeyJob.perform_now(@task.id)
    end

    assert_equal "todo-remote-1", @task.reload.hey_mirrored_todo_id
  end

  test "skips when mirrored id already set" do
    @task.update_column(:hey_mirrored_todo_id, "existing")

    called = false
    client = Object.new
    client.define_singleton_method(:create_todo) { |**_| called = true }

    with_hey_client(client) do
      SyncInboxSometimeTodoToHeyJob.perform_now(@task.id)
    end

    assert_equal false, called
  end

  test "skips without hey_app_url" do
    @task.update_column(:hey_app_url, nil)

    called = false
    client = Object.new
    client.define_singleton_method(:create_todo) { |**_| called = true }

    with_hey_client(client) do
      SyncInboxSometimeTodoToHeyJob.perform_now(@task.id)
    end

    assert_equal false, called
  end
end
