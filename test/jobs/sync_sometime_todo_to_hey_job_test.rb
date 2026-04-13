require "test_helper"

class SyncSometimeTodoToHeyJobTest < ActiveJob::TestCase
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
      title: "Sometime task",
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
      SyncSometimeTodoToHeyJob.perform_now(@task.id)
    end

    assert_equal "todo-remote-1", @task.reload.hey_mirrored_todo_id
  end

  test "skips when mirrored id already set" do
    @task.update_column(:hey_mirrored_todo_id, "existing")

    called = false
    client = Object.new
    client.define_singleton_method(:create_todo) { |**_| called = true }

    with_hey_client(client) do
      SyncSometimeTodoToHeyJob.perform_now(@task.id)
    end

    assert_equal false, called
  end

  test "creates todo without hey_app_url using week end anchor date" do
    @task.update_column(:hey_app_url, nil)

    captured = nil
    client = Object.new
    client.define_singleton_method(:create_todo) do |**kw|
      captured = kw
      { "id" => "todo-remote-2" }
    end

    with_hey_client(client) do
      SyncSometimeTodoToHeyJob.perform_now(@task.id)
    end

    assert captured
    assert_equal "Sometime task", captured[:title]
    assert_equal "2026-04-19", captured[:starts_at]
    assert_equal "todo-remote-2", @task.reload.hey_mirrored_todo_id
  end
end
