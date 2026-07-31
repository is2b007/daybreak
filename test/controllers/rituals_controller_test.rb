require "test_helper"

class RitualsControllerTest < ActionController::TestCase
  setup do
    @user = users(:one)
    session[:user_id] = @user.id
    @today = @user.today_in_zone
    @day_plan = @user.day_plans.find_or_create_by!(date: @today)
  end

  test "GET morning step 1 renders with no data" do
    get :morning, params: { step: 1 }
    assert_response :success
  end

  test "GET morning records last_open_date on first hit; reload does not reset it" do
    @user.update_column(:last_open_date, @today - 1.day)

    get :morning, params: { step: 1 }
    assert_equal @today, @user.reload.last_open_date

    # Second hit same day — still today, no change.
    get :morning, params: { step: 1 }
    assert_equal @today, @user.reload.last_open_date
  end

  test "GET evening step 1 aggregates planned minutes via SQL (completed with no actual falls back to planned for actual column)" do
    @day_plan.task_assignments.create!(
      user: @user, title: "Done, no actual", status: :completed,
      planned_duration_minutes: 45, actual_duration_minutes: nil
    )
    @day_plan.task_assignments.create!(
      user: @user, title: "Done, with actual", status: :completed,
      planned_duration_minutes: 30, actual_duration_minutes: 50
    )
    @day_plan.task_assignments.create!(
      user: @user, title: "Pending", status: :pending,
      planned_duration_minutes: 60, actual_duration_minutes: nil
    )

    get :evening, params: { step: 1 }
    assert_response :success
  end

  test "GET evening/complete records last_sunset_played_date on first hit of the day" do
    @user.update_column(:last_sunset_played_date, nil)

    get :evening_complete
    assert_equal @today, @user.reload.last_sunset_played_date
  end

  # The reflection box is prefilled with the day's journal, and used to submit over
  # it from empty — wiping anything written in the day-view scratchpad.
  test "POST evening step 2 keeps the day's journal when the reflection is unchanged" do
    @user.local_journal_entries.create!(
      date: @today, content: "<p>Morning notes worth keeping.</p>"
    )

    post :evening_update, params: { step: 2, reflection: "Morning notes worth keeping." }

    entry = @user.local_journal_entries.find_by(date: @today)
    assert_includes entry.content, "Morning notes worth keeping."
  end

  test "POST evening step 2 stores the reflection as HTML so line breaks survive" do
    post :evening_update, params: { step: 2, reflection: "One line.\n\nAnd another." }

    entry = @user.local_journal_entries.find_by(date: @today)
    assert_includes entry.content, "<p>One line.</p>"
    assert_includes entry.content, "<p>And another.</p>"
  end

  test "POST evening step 2 with a cleared box removes the entry" do
    @user.local_journal_entries.create!(date: @today, content: "<p>Gone soon.</p>")

    post :evening_update, params: { step: 2, reflection: "   " }

    assert_nil @user.local_journal_entries.find_by(date: @today)
  end

  test "GET evening/complete creates the day plan when none exists" do
    @day_plan.destroy!

    get :evening_complete

    plan = @user.day_plans.find_by(date: @today)
    assert_not_nil plan
    assert_predicate plan, :evening_ritual_done?
  end

  test "POST evening step 1 defers remaining tasks per decision" do
    keep = @user.task_assignments.create!(
      day_plan: @day_plan, title: "Push to tomorrow", source: :local,
      week_start_date: @user.current_week_start, week_bucket: "day",
      size: :medium, status: :pending, position: 0
    )
    drop = @user.task_assignments.create!(
      day_plan: @day_plan, title: "Let go", source: :local,
      week_start_date: @user.current_week_start, week_bucket: "day",
      size: :medium, status: :pending, position: 1
    )

    post :evening_update, params: {
      step: 1, tasks: { keep.id.to_s => "tomorrow", drop.id.to_s => "let_go" }
    }

    assert_equal @user.today_in_zone + 1.day, keep.reload.day_plan.date
    assert_predicate drop.reload, :deferred?
  end
end
