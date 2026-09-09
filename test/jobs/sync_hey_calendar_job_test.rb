require "test_helper"

class SyncHeyCalendarJobTest < ActiveJob::TestCase
  parallelize(workers: 1)

  setup do
    @user = users(:one)
    @user.update!(
      hey_access_token: "stub",
      hey_refresh_token: "stub-r",
      hey_token_expires_at: 2.weeks.from_now
    )
  end

  def with_hey_client(client)
    original = HeyClient.method(:new)
    HeyClient.define_singleton_method(:new) { |_u| client }
    yield
  ensure
    HeyClient.define_singleton_method(:new, original)
  end

  test "upserts hey todos from a complete fetch" do
    client = Object.new
    client.define_singleton_method(:todos) do
      [ { "id" => "100", "title" => "Buy milk", "completed" => false } ]
    end
    client.define_singleton_method(:recordings_complete?) { true }

    with_hey_client(client) do
      SyncHeyCalendarJob.perform_now(@user.id)
    end

    row = @user.task_assignments.find_by(external_id: "100", source: :hey)
    assert row
    assert_equal "Buy milk", row.title
    assert row.pending?
  end

  test "prunes hey todos missing from a complete fetch" do
    stale = @user.task_assignments.create!(
      source: :hey,
      external_id: "old-todo",
      title: "Deleted in HEY",
      week_bucket: "sometime",
      week_start_date: @user.current_week_start,
      size: :medium,
      status: :pending
    )
    mirrored = @user.task_assignments.create!(
      source: :local,
      title: "Local mirror",
      week_bucket: "sometime",
      week_start_date: @user.current_week_start,
      size: :medium,
      status: :pending,
      hey_mirrored_todo_id: "old-todo"
    )

    client = Object.new
    client.define_singleton_method(:todos) do
      [ { "id" => "100", "title" => "Still here", "completed" => false } ]
    end
    client.define_singleton_method(:recordings_complete?) { true }

    with_hey_client(client) do
      SyncHeyCalendarJob.perform_now(@user.id)
    end

    assert_not TaskAssignment.exists?(stale.id)
    assert TaskAssignment.exists?(mirrored.id)
    assert @user.task_assignments.exists?(external_id: "100", source: :hey)
  end

  test "does not prune when todos fetch is nil" do
    stale = @user.task_assignments.create!(
      source: :hey,
      external_id: "keep-nil",
      title: "Keep",
      week_bucket: "sometime",
      week_start_date: @user.current_week_start,
      size: :medium,
      status: :pending
    )

    client = Object.new
    client.define_singleton_method(:todos) { nil }

    with_hey_client(client) do
      SyncHeyCalendarJob.perform_now(@user.id)
    end

    assert TaskAssignment.exists?(stale.id)
  end

  test "does not prune when recordings pagination is incomplete" do
    stale = @user.task_assignments.create!(
      source: :hey,
      external_id: "keep-incomplete",
      title: "Keep",
      week_bucket: "sometime",
      week_start_date: @user.current_week_start,
      size: :medium,
      status: :pending
    )

    client = Object.new
    client.define_singleton_method(:todos) { [] }
    client.define_singleton_method(:recordings_complete?) { false }

    with_hey_client(client) do
      SyncHeyCalendarJob.perform_now(@user.id)
    end

    assert TaskAssignment.exists?(stale.id)
  end

  test "empty complete fetch prunes source hey todos" do
    stale = @user.task_assignments.create!(
      source: :hey,
      external_id: "empty-gone",
      title: "Gone",
      week_bucket: "sometime",
      week_start_date: @user.current_week_start,
      size: :medium,
      status: :pending
    )

    client = Object.new
    client.define_singleton_method(:todos) { [] }
    client.define_singleton_method(:recordings_complete?) { true }

    with_hey_client(client) do
      SyncHeyCalendarJob.perform_now(@user.id)
    end

    assert_not TaskAssignment.exists?(stale.id)
  end
end
