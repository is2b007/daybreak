class AddHeyInstallIdToUsers < ActiveRecord::Migration[8.1]
  def change
    # The install HEY bound this user's tokens to (a UUIDv4, hey-cli's model). Blank for
    # credentials issued before Daybreak minted one; those keep the legacy id.
    add_column :users, :hey_install_id, :string
    # Set when HEY refuses the stored credentials, so the app can ask for a reconnect.
    add_column :users, :hey_reconnect_needed_at, :datetime
  end
end
