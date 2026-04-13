class AddBasecampAvatarUrlToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :basecamp_avatar_url, :string
  end
end
