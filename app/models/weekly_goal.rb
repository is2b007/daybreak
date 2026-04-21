class WeeklyGoal < ApplicationRecord
  belongs_to :user

  validates :title, presence: true
  validates :week_start_date, presence: true

  scope :for_week, ->(week_start) { where(week_start_date: week_start).order(:position, :id) }
  scope :incomplete, -> { where(completed: false) }
  scope :completed, -> { where(completed: true) }

  # Preloaded per-week totals to avoid N+1 in right-panel / week views.
  # Goals all share a week, so one grouped query replaces one-query-per-goal.
  # Callers pass the returned hash into `progress_text(preloaded:)`.
  def self.progress_totals_for_week(user, week_start)
    rows = TaskAssignment
      .where(user: user, week_start_date: week_start)
      .group(:status)
      .count
    total = rows.values.sum
    done = rows[TaskAssignment.statuses[:completed]].to_i
    { total: total, done: done }
  end

  def progress_text(preloaded: nil)
    if preloaded
      "#{preloaded[:done]}/#{preloaded[:total]}"
    else
      tasks = TaskAssignment.where(user: user, week_start_date: week_start_date)
      "#{tasks.completed.count}/#{tasks.count}"
    end
  end
end
