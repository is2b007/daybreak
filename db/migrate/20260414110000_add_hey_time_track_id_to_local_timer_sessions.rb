class AddHeyTimeTrackIdToLocalTimerSessions < ActiveRecord::Migration[8.0]
  def change
    add_column :local_timer_sessions, :hey_time_track_id, :string
  end
end
