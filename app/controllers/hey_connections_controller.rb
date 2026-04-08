class HeyConnectionsController < ApplicationController
  skip_before_action :require_onboarding!, only: [:create]

  def new
    redirect_to HeyClient.authorize_url(auth_hey_callback_url), allow_other_host: true
  end

  def create
    token_data = HeyClient.exchange_code(params[:code], auth_hey_callback_url)

    current_user.update!(
      hey_access_token: token_data["access_token"],
      hey_refresh_token: token_data["refresh_token"],
      hey_token_expires_at: 2.weeks.from_now
    )

    if current_user.onboarded?
      redirect_to settings_path, notice: "HEY connected."
    else
      redirect_to onboarding_path(step: 4)
    end
  rescue HeyClient::AuthError => e
    if current_user.onboarded?
      redirect_to settings_path, alert: "Couldn't connect HEY. Want to try again?"
    else
      redirect_to onboarding_path(step: 3), alert: "Couldn't connect HEY. You can skip and connect later from Settings."
    end
  end

  def destroy
    current_user.update!(hey_access_token: nil, hey_refresh_token: nil, hey_token_expires_at: nil)
    redirect_to settings_path, notice: "HEY disconnected."
  end
end
