class WeeklyGoal < ApplicationRecord
  belongs_to :user

  validates :title, presence: true
  validates :week_start_date, presence: true

  scope :for_week, ->(week_start) { where(week_start_date: week_start) }
  scope :incomplete, -> { where(completed: false) }
  scope :completed, -> { where(completed: true) }

  def progress_text
    tasks = TaskAssignment.where(user: user, week_start_date: week_start_date)
    done = tasks.completed.count
    total = tasks.count
    "#{done}/#{total}"
  end
end
