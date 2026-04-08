class DayPlan < ApplicationRecord
  belongs_to :user
  has_many :task_assignments, dependent: :nullify

  enum :status, { planning: 0, active: 1, completed: 2 }

  validates :date, presence: true, uniqueness: { scope: :user_id }

  scope :for_date, ->(date) { where(date: date) }
  scope :for_week, ->(week_start) { where(date: week_start..week_start + 6.days) }

  def total_planned_minutes
    task_assignments.sum(:planned_duration_minutes)
  end

  def total_actual_minutes
    task_assignments.where.not(actual_duration_minutes: nil).sum(:actual_duration_minutes)
  end

  def completed_count
    task_assignments.completed.count
  end

  def pending_count
    task_assignments.pending.count
  end
end
