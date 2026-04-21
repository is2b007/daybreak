class AddLastSunsetPlayedDateToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :last_sunset_played_date, :date
  end
end
