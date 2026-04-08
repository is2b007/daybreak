class SessionsController < ApplicationController
  skip_before_action :authenticate_user!
  skip_before_action :require_onboarding!

  def new
    redirect_to root_path if logged_in?
  end

  def create
    token_data = BasecampClient.exchange_code(params[:code], auth_basecamp_callback_url)
    identity_data = BasecampClient.fetch_identity(token_data["access_token"])

    identity = identity_data["identity"]
    account = identity_data["accounts"]&.find { |a| a["product"] == "bc3" }

    user = User.find_or_initialize_by(basecamp_uid: identity["id"].to_s)
    user.assign_attributes(
      name: user.new_record? ? identity["first_name"] : user.name,
      email: identity["email_address"],
      basecamp_access_token: token_data["access_token"],
      basecamp_refresh_token: token_data["refresh_token"],
      basecamp_token_expires_at: 2.weeks.from_now,
      basecamp_account_id: account&.dig("id")&.to_s
    )
    user.save!

    session[:user_id] = user.id

    if user.onboarded?
      redirect_to root_path
    else
      redirect_to onboarding_path
    end
  rescue BasecampClient::AuthError => e
    redirect_to login_path, alert: "Authentication failed. Please try again."
  end

  def destroy
    session.delete(:user_id)
    redirect_to login_path, notice: "Signed out."
  end
end
