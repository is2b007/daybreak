class LocalTimerSession < ApplicationRecord
  belongs_to :user
  belongs_to :task_assignment, optional: true

  validates :started_at, presence: true

  scope :running, -> { where(ended_at: nil) }

  def stop!
    update!(ended_at: Time.current)
    update_task_duration! if task_assignment
  end

  def duration_seconds
    ((ended_at || Time.current) - started_at).to_i
  end

  def duration_minutes
    (duration_seconds / 60.0).round
  end

  def running?
    ended_at.nil?
  end

  private

  def update_task_duration!
    total = user.local_timer_sessions
      .where(task_assignment: task_assignment)
      .where.not(ended_at: nil)
      .sum { |s| s.duration_minutes }
    task_assignment.update!(actual_duration_minutes: total)
  end
end
