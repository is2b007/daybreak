require "test_helper"

class TaskAssignmentsControllerTest < ActionController::TestCase
  setup do
    @user = users(:one)
    session[:user_id] = @user.id

    @source_plan = @user.day_plans.create!(date: Date.parse("2026-04-07"))
    @task = @user.task_assignments.create!(
      day_plan: @source_plan,
      title: "Ship spec 01",
      week_start_date: Date.parse("2026-04-06"),
      week_bucket: "day",
      position: 0
    )
  end

  test "focus renders HTML when Turbo follows a redirect asking for a stream" do
    @request.accept = "text/vnd.turbo-stream.html, text/html, application/xhtml+xml"
    get :focus, params: { id: @task.id }
    assert_response :success
    assert_includes @response.body, "Ship spec 01"
  end

  test "PATCH restore_hey_email clears triage and destroys task" do
    email = @user.hey_emails.create!(
      external_id: "restore-1",
      folder: :imbox,
      subject: "Restorable",
      received_at: 1.hour.ago,
      hey_url: "https://app.hey.com/topics/restore-1",
      triaged_at: Time.current
    )
    task = @user.task_assignments.create!(
      day_plan: @source_plan,
      title: "Restorable",
      hey_app_url: email.hey_url,
      week_start_date: Date.parse("2026-04-06"),
      week_bucket: "day",
      position: 0,
      source: :local,
      size: :medium,
      status: :pending
    )
    patch :restore_hey_email, params: { id: task.id }, format: :turbo_stream
    assert_response :success
    assert_nil email.reload.triaged_at
    assert_raises(ActiveRecord::RecordNotFound) { task.reload }
  end

  test "PATCH update saves private notes without touching the synced description" do
    @task.update!(description: "<div>From Basecamp</div>")
    patch :update, params: { id: @task.id, task_assignment: { notes: "Call Jason first" } }, format: :turbo_stream
    assert_equal "Call Jason first", @task.reload.notes
    assert_equal "<div>From Basecamp</div>", @task.description
  end

  test "PATCH move renders turbo stream (regression for missing template)" do
    patch :move,
      params: { id: @task.id, target_date: "2026-04-09", position: 0, source_date: "2026-04-07" },
      format: :turbo_stream

    assert_response :success
    assert_equal Date.parse("2026-04-09"), @task.reload.day_plan.date
    assert_match(/day_2026-04-09/, @response.body)
    assert_match(/day_2026-04-07/, @response.body)
  end

  test "PATCH complete on a day task appends to that day's completed bucket" do
    patch :complete, params: { id: @task.id }, format: :turbo_stream

    assert_response :success
    assert_predicate @task.reload, :completed?
    assert_match(/day_2026-04-07_completed/, @response.body)
  end

  # The append target used to be "day_#{plan&.date}_completed". A sometime task has
  # no plan, so it addressed "day__completed", Turbo dropped the append, and the
  # card vanished from the board with nowhere to land.
  test "PATCH complete on a sometime task re-renders the sometime row" do
    task = sometime_task

    patch :complete, params: { id: task.id }, format: :turbo_stream

    assert_response :success
    assert_predicate task.reload, :completed?
    assert_match(/sometime_row/, @response.body)
    assert_no_match(/day__completed/, @response.body)
  end

  # Deferring only removed the card; nothing re-rendered the destination, so the
  # task disappeared from the board until a full reload.
  test "PATCH defer to tomorrow re-renders both the source and target columns" do
    travel_to Time.zone.parse("2026-04-07 09:00:00") do
      patch :defer, params: { id: @task.id, defer_to: "tomorrow" }, format: :turbo_stream

      assert_response :success
      tomorrow = @user.today_in_zone + 1.day
      assert_equal tomorrow, @task.reload.day_plan.date
      assert_match(/day_2026-04-07/, @response.body)
      assert_match(/day_#{tomorrow}/, @response.body)
    end
  end

  test "PATCH defer to sometime re-renders the sometime row" do
    patch :defer, params: { id: @task.id, defer_to: "sometime" }, format: :turbo_stream

    assert_response :success
    assert_equal "sometime", @task.reload.week_bucket
    assert_match(/sometime_row/, @response.body)
  end

  test "PATCH defer with an unknown destination is a bad request" do
    patch :defer, params: { id: @task.id, defer_to: "nowhere" }, format: :turbo_stream

    assert_response :bad_request
    assert_equal "day", @task.reload.week_bucket
  end

  test "PATCH timebox clamps an out-of-range hour instead of raising" do
    patch :timebox,
      params: { id: @task.id, date: "2026-04-07", hour: "99", minute: "410" },
      format: :turbo_stream

    assert_response :success
    assert_predicate @task.reload, :timeboxed?
  end

  test "PATCH move with an unparseable date is a bad request" do
    patch :move,
      params: { id: @task.id, target_date: "not-a-date", position: 0 },
      format: :turbo_stream

    assert_response :bad_request
  end

  # Replacing only the list left the counts, progress bar and the typed title
  # in the add field stale, so the day view refreshes instead.
  test "POST create from the day view refreshes the page" do
    post :create,
      params: { date: "2026-04-07", title: "Added from the day view", view: "day" },
      format: :turbo_stream

    assert_response :success
    assert_includes @response.body, %(<turbo-stream action="refresh">)
    assert @user.task_assignments.exists?(title: "Added from the day view")
  end

  test "POST create from the week board targets the day column" do
    post :create,
      params: { date: "2026-04-07", title: "Added from the board" },
      format: :turbo_stream

    assert_response :success
    assert_match(/day_2026-04-07/, @response.body)
    assert_includes @response.body, "Added from the board"
  end

  private

  def sometime_task
    @user.task_assignments.create!(
      title: "Someday thing",
      source: :local,
      week_start_date: @user.current_week_start,
      week_bucket: "sometime",
      size: :medium,
      status: :pending,
      position: 0
    )
  end

  test "PATCH stage moves a Basecamp card and remembers the column" do
    card = @user.task_assignments.create!(title: "Hero art", source: :basecamp, external_id: "77",
      basecamp_recording_type: TaskAssignment::BASECAMP_CARD_TYPE, week_bucket: "inbox")
    moves = []
    fake = Object.new
    fake.define_singleton_method(:move_card) { |id, column| moves << [ id, column ] }
    fake.define_singleton_method(:comments) { |*| [] }
    fake.define_singleton_method(:card_columns) { |_id| { current_id: "42", columns: [ { "id" => 42, "title" => "Review", "type" => "Kanban::Column" } ] } }
    with_basecamp_client(fake) do
      patch :stage, params: { id: card.id, column_id: "42", column_title: "Review", column_type: "Kanban::Column" }, format: :turbo_stream
    end

    assert_equal [ [ "77", "42" ] ], moves
    assert_equal "Review", card.reload.basecamp_column_name
    assert_not card.completed?
  end

  test "PATCH stage into the Done column completes the card" do
    card = @user.task_assignments.create!(title: "Hero art", source: :basecamp, external_id: "77",
      basecamp_recording_type: TaskAssignment::BASECAMP_CARD_TYPE, week_bucket: "inbox")
    fake = Object.new
    fake.define_singleton_method(:move_card) { |*| nil }
    fake.define_singleton_method(:card_columns) { |_id| nil }
    fake.define_singleton_method(:comments) { |*| [] }
    with_basecamp_client(fake) do
      patch :stage, params: { id: card.id, column_id: "9", column_title: "Done", column_type: BasecampClient::DONE_COLUMN_TYPE }, format: :turbo_stream
    end

    assert card.reload.completed?
  end

  def with_basecamp_client(fake)
    original = BasecampClient.method(:new)
    BasecampClient.define_singleton_method(:new) { |*_args| fake }
    yield
  ensure
    BasecampClient.define_singleton_method(:new, original)
  end
end
