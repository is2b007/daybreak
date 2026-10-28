class SessionsController < ApplicationController
  skip_before_action :authenticate_user!
  skip_before_action :require_onboarding!

  # Comma-separated Basecamp identity ids allowed in besides the install's owner.
  ALLOWED_IDS_ENV = "DAYBREAK_ALLOWED_BASECAMP_IDS"

  def new
    # A native app opened this in the system browser: sign in here, then hand
    # the session back to the app (NativeSignIn). A plain web sign-in clears it.
    if params[:native].present?
      session[:native_sign_in] = true
    else
      session.delete(:native_sign_in)
    end

    if logged_in?
      return redirect_to(NativeSignIn.app_url(current_user), allow_other_host: true) if session.delete(:native_sign_in)
      return redirect_to root_path
    end
    return unless BasecampClient.configured?

    session[:basecamp_oauth_state] = SecureRandom.urlsafe_base64(24)
    @authorize_url = BasecampClient.authorize_url(auth_basecamp_callback_url, state: session[:basecamp_oauth_state])
    redirect_to @authorize_url, allow_other_host: true if params[:native].present?
  end

  def create
    expected_state = session.delete(:basecamp_oauth_state)
    unless expected_state.present? && params[:state].present? &&
           ActiveSupport::SecurityUtils.secure_compare(expected_state, params[:state].to_s)
      redirect_to login_path, alert: "That sign-in link expired. Want to try again?"
      return
    end
    if params[:code].blank?
      redirect_to login_path, alert: params[:error_description].presence || "Basecamp didn't sign you in. Want to try again?"
      return
    end

    token_data = BasecampClient.exchange_code(params[:code], auth_basecamp_callback_url)
    identity_data = BasecampClient.fetch_identity(token_data["access_token"])

    identity = identity_data.is_a?(Hash) ? identity_data["identity"] : nil
    if identity.blank? || identity["id"].blank?
      Rails.logger.warn("Basecamp identity response had no identity id")
      redirect_to login_path, alert: "Basecamp didn't send back your account. Want to try again?"
      return
    end

    unless sign_in_allowed?(identity["id"].to_s)
      Rails.logger.warn("Refused Basecamp sign-in for identity #{identity["id"]}: not this install's owner")
      redirect_to login_path, alert: "This Daybreak belongs to someone else. Ask its owner to add your Basecamp ID to #{ALLOWED_IDS_ENV}."
      return
    end

    account = BasecampClient.pick_account(identity_data["accounts"])

    user = User.find_or_initialize_by(basecamp_uid: identity["id"].to_s)
    user.assign_attributes(
      name: user.new_record? ? identity["first_name"] : user.name,
      email: identity["email_address"],
      basecamp_access_token: token_data["access_token"],
      basecamp_refresh_token: token_data["refresh_token"],
      basecamp_token_expires_at: BasecampClient.expires_at_from_token(token_data),
      basecamp_account_id: BasecampClient.account_id_from(account)
    )
    user.save!

    user.sync_basecamp_avatar_url_from_api!

    begin
      SyncBasecampAssignmentsJob.perform_now(user.id)
    rescue StandardError => e
      Rails.logger.warn("Basecamp assignment sync on login failed: #{e.class}: #{e.message}")
      SyncBasecampAssignmentsJob.perform_later(user.id)
    end
    SyncCalendarEventsJob.perform_later(user.id)

    native = session.delete(:native_sign_in)
    session[:user_id] = user.id

    if native
      redirect_to NativeSignIn.app_url(user), allow_other_host: true
    elsif user.onboarded?
      redirect_to root_path
    else
      redirect_to onboarding_path
    end
  rescue BasecampClient::AuthError => e
    Rails.logger.warn("Basecamp sign-in failed: #{e.message}")
    redirect_to login_path, alert: "That didn't go through. Want to try again?"
  end

  def destroy
    session.delete(:user_id)
    redirect_to login_path, notice: "Signed out. See you tomorrow."
  end

  private

  # Daybreak is single-user: the first Basecamp identity to sign in owns the install.
  # Anyone already here keeps access; others need to be listed in ALLOWED_IDS_ENV.
  def sign_in_allowed?(basecamp_uid)
    return true if User.none? || User.exists?(basecamp_uid: basecamp_uid)

    ENV[ALLOWED_IDS_ENV].to_s.split(",").map(&:strip).include?(basecamp_uid)
  end
end
