class HeyConnectionsController < ApplicationController
  def new
    # TODO: Redirect to HEY OAuth when available
    # For now, redirect back with a message
    redirect_to settings_path, notice: "HEY connection coming soon."
  end

  def create
    # TODO: Handle HEY OAuth callback
    # token_data = HeyClient.exchange_code(params[:code], auth_hey_callback_url)
    # current_user.update!(
    #   hey_access_token: token_data["access_token"],
    #   hey_refresh_token: token_data["refresh_token"],
    #   hey_token_expires_at: 2.weeks.from_now
    # )
    redirect_to settings_path, notice: "HEY connected."
  end

  def destroy
    current_user.update!(hey_access_token: nil, hey_refresh_token: nil, hey_token_expires_at: nil)
    redirect_to settings_path, notice: "HEY disconnected."
  end
end
