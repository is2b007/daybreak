class HeyConnectionsController < ApplicationController
  skip_before_action :require_onboarding!, only: [ :callback ]
  skip_before_action :authenticate_user!, only: [ :callback ]

  # GET /auth/hey
  # Renders the "Connect HEY via CLI" page with step-by-step token instructions.
  def new
  end

  # POST /auth/hey
  # Accepts a bearer token pasted from `hey auth token` and stores it.
  def create
    token = params[:token].to_s.strip

    if token.blank?
      flash.now[:alert] = "Paste a token from the HEY CLI before connecting."
      render :new, status: :unprocessable_entity
      return
    end

    # Verify the token against the HEY identity endpoint before persisting.
    begin
      HeyClient.fetch_identity(token)
    rescue HeyClient::AuthError, StandardError
      flash.now[:alert] = "That token didn't work — make sure you copied the full output of `hey auth token`."
      render :new, status: :unprocessable_entity
      return
    end

    current_user.update!(
      hey_access_token:     token,
      hey_refresh_token:    nil,
      hey_token_expires_at: 2.weeks.from_now
    )

    SyncHeyCalendarJob.perform_later(current_user.id)
    SyncHeyEmailsJob.perform_later(current_user.id)
    SyncCalendarEventsJob.perform_later(current_user.id)

    if current_user.onboarded?
      redirect_to settings_path, notice: "HEY is connected."
    else
      redirect_to onboarding_path(step: 4)
    end
  end

  # DELETE /auth/hey
  def destroy
    current_user.hey_emails.delete_all
    current_user.calendar_events.hey.delete_all
    current_user.update!(
      hey_access_token:     nil,
      hey_refresh_token:    nil,
      hey_token_expires_at: nil
    )
    redirect_to settings_path, notice: "HEY is disconnected."
  end

  # GET /auth/hey/callback
  # Kept for the PKCE OAuth flow — currently HEY's redirect_uri validation blocks
  # third-party apps, so this path is not reachable in practice. Preserved for when
  # 37signals opens up OAuth registration.
  def callback
    if params[:error].present?
      Rails.logger.warn("HEY OAuth denied: #{params[:error]} — #{params[:error_description]}")
      redirect_after_hey_failure(params[:error_description].presence || "HEY connection was cancelled.")
      return
    end

    unless params[:code].present? && params[:state].present?
      redirect_after_hey_failure("Something went wrong. Please try again.")
      return
    end

    payload = Rails.cache.read(hey_oauth_cache_key(params[:state]))
    Rails.cache.delete(hey_oauth_cache_key(params[:state]))

    unless payload
      Rails.logger.warn("HEY OAuth: cache miss for state (expired or invalid)")
      redirect_to login_path, alert: "Connection timed out. Sign in and click Connect HEY again."
      return
    end

    user = User.find_by(id: payload[:user_id])
    unless user
      redirect_to login_path, alert: "Account not found."
      return
    end

    token_data = HeyClient.exchange_code(params[:code], payload[:redirect_uri], code_verifier: payload[:verifier])
    expires_in = token_data["expires_in"]&.to_i
    expires_at = expires_in&.positive? ? expires_in.seconds.from_now : 2.weeks.from_now

    user.update!(
      hey_access_token:     token_data["access_token"],
      hey_refresh_token:    token_data["refresh_token"],
      hey_token_expires_at: expires_at
    )
    session[:user_id] = user.id

    SyncHeyCalendarJob.perform_later(user.id)
    SyncHeyEmailsJob.perform_later(user.id)
    SyncCalendarEventsJob.perform_later(user.id)

    user.onboarded? ? redirect_to(settings_path, notice: "HEY is connected.") : redirect_to(onboarding_path(step: 4))
  rescue HeyClient::AuthError => e
    Rails.logger.warn("HEY OAuth callback error: #{e.message}")
    session[:user_id] = user.id if user
    redirect_after_hey_failure("Couldn't connect HEY. Want to try again?")
  end

  private

  def hey_oauth_cache_key(state)
    "hey_oauth/v1/#{Digest::SHA256.hexdigest(state.to_s)}"
  end

  def redirect_after_hey_failure(message)
    logged_in? ? redirect_to(settings_path, alert: message) : redirect_to(login_path, alert: message)
  end
end
