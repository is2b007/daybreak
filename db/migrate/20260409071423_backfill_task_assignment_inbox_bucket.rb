class BackfillTaskAssignmentInboxBucket < ActiveRecord::Migration[8.0]
  def up
    # All tasks that were auto-placed in "sometime" without a day_plan are
    # effectively unscheduled inbox items. Move them to "inbox" so they only
    # appear in the right-panel inbox, not the "Sometime this week" board row.
    # Tasks in "day" bucket (explicitly scheduled) are left untouched.
    TaskAssignment.where(week_bucket: "sometime", day_plan_id: nil)
                  .update_all(week_bucket: "inbox", week_start_date: nil)
  end

  def down
    # Reversing: move inbox tasks back to sometime with the current week_start
    week_start = Date.current.beginning_of_week(:monday)
    TaskAssignment.where(week_bucket: "inbox")
                  .update_all(week_bucket: "sometime", week_start_date: week_start)
  end
end
