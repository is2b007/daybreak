class AddPositionToWeeklyGoals < ActiveRecord::Migration[8.1]
  def up
    add_column :weekly_goals, :position, :integer, default: 0, null: false

    # Backfill position from current row order within each (user, week).
    # SQLite-friendly: no window functions needed — one pass per (user, week).
    WeeklyGoal.reset_column_information
    WeeklyGoal.connection.select_rows(
      "SELECT DISTINCT user_id, week_start_date FROM weekly_goals"
    ).each do |user_id, week_start_date|
      WeeklyGoal.where(user_id: user_id, week_start_date: week_start_date)
        .order(:id)
        .each_with_index { |goal, idx| goal.update_columns(position: idx) }
    end

    add_index :weekly_goals,
      [ :user_id, :week_start_date, :position ],
      unique: true,
      name: "index_weekly_goals_on_user_week_position"
  end

  def down
    remove_index :weekly_goals, name: "index_weekly_goals_on_user_week_position"
    remove_column :weekly_goals, :position
  end
end
