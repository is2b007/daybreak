class HeyConnectionsController < ApplicationController
  # Onboarding step 5 sends people here before they are onboarded; requiring onboarding
  # bounced them straight back to the onboarding page.
  skip_before_action :require_onboarding!
  skip_before_action :authenticate_user!, only: [ :callback ]

  # GET /auth/hey
  # Renders the "Connect HEY" page: the OAuth button, with the CLI token paste tucked away.
  def new
  end

  # HEY's public OAuth client only accepts loopback redirects (RFC 8252), so a hosted
  # Daybreak can't receive the callback. HEY sends that browser to this port on its own
  # machine instead; nothing listens there, and the user pastes the address back (#complete).
  PASTE_REDIRECT_PORT = 47823
  LOOPBACK_HOSTS = %w[127.0.0.1 localhost ::1].freeze

  # GET /auth/hey/authorize
  # Starts PKCE OAuth. Running locally, HEY redirects straight back to #callback.
  # Hosted, it renders the paste step and opens HEY in a new tab.
  def authorize
    verifier = HeyClient.generate_code_verifier
    challenge = HeyClient.generate_code_challenge(verifier)
    state = SecureRandom.hex(24)
    install_id = current_user.hey_install_id.presence || HeyClient.generate_install_id

    redirect_uri = if loopback_request?
      auth_hey_callback_url(protocol: "http", host: "127.0.0.1", port: request.port)
    else
      "http://127.0.0.1:#{PASTE_REDIRECT_PORT}/auth/hey/callback"
    end

    Rails.cache.write(
      hey_oauth_cache_key(state),
      { user_id: current_user.id, verifier: verifier, redirect_uri: redirect_uri, install_id: install_id },
      expires_in: 10.minutes
    )

    authorize_url = HeyClient.authorize_url(redirect_uri, code_challenge: challenge, state: state, install_id: install_id)

    if loopback_request?
      redirect_to authorize_url, allow_other_host: true
    else
      @authorize_url = authorize_url
      render :paste
    end
  end

  # POST /auth/hey/complete
  # The hosted half of #authorize: reads code and state out of the address HEY sent the
  # browser to. The code is useless without the PKCE verifier, which never left the server.
  def complete
    query = begin
      Rack::Utils.parse_query(URI.parse(params[:callback_url].to_s.strip).query.to_s)
    rescue URI::InvalidURIError
      {}
    end

    if query["error"].present?
      redirect_to auth_hey_path, alert: query["error_description"].presence || "HEY connection was cancelled."
    elsif query["code"].blank? || query["state"].blank?
      redirect_to auth_hey_path, alert: "That address didn't come from HEY. Copy the whole address of the page HEY sent you to, then try again."
    else
      finish_hey_oauth(code: query["code"], state: query["state"], expected_user: current_user)
    end
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
      hey_token_expires_at: 2.weeks.from_now,
      hey_reconnect_needed_at: nil
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
    current_user.calendar_events.where(source: [ :hey, :daybreak ]).delete_all
    current_user.update!(
      hey_access_token:     nil,
      hey_refresh_token:    nil,
      hey_token_expires_at: nil,
      hey_reconnect_needed_at: nil
    )
    redirect_to settings_path, notice: "HEY is disconnected."
  end

  # GET /auth/hey/callback
  # PKCE OAuth callback: exchanges the authorization code for access + refresh tokens.
  # Uses 127.0.0.1 redirect_uri (same pattern as hey-cli's localhost OAuth flow).
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

    finish_hey_oauth(code: params[:code], state: params[:state])
  end

  private

  # Exchanges the code for tokens and stores them with the install id they were issued to.
  # +expected_user+ is the signed-in user on the paste path; the loopback callback runs
  # without a session (127.0.0.1 is a different cookie host), so the cached state names the user.
  def finish_hey_oauth(code:, state:, expected_user: nil)
    payload = Rails.cache.read(hey_oauth_cache_key(state))
    Rails.cache.delete(hey_oauth_cache_key(state))

    unless payload
      Rails.logger.warn("HEY OAuth: cache miss for state (expired or invalid)")
      redirect_after_hey_failure("That connection attempt expired. Click Connect with HEY again.")
      return
    end

    user = User.find_by(id: payload[:user_id])
    if user.nil? || (expected_user && expected_user.id != user.id)
      redirect_after_hey_failure("Account not found.")
      return
    end

    token_data = HeyClient.exchange_code(
      code, payload[:redirect_uri],
      code_verifier: payload[:verifier],
      install_id: payload[:install_id].presence || HeyClient::LEGACY_INSTALL_ID
    )
    expires_in = token_data["expires_in"]&.to_i
    expires_at = expires_in&.positive? ? expires_in.seconds.from_now : 2.weeks.from_now

    user.update!(
      hey_access_token:        token_data["access_token"],
      hey_refresh_token:       token_data["refresh_token"],
      hey_token_expires_at:    expires_at,
      hey_install_id:          payload[:install_id].presence,
      hey_reconnect_needed_at: nil
    )
    session[:user_id] = user.id

    SyncHeyCalendarJob.perform_later(user.id)
    SyncHeyEmailsJob.perform_later(user.id)
    SyncCalendarEventsJob.perform_later(user.id)

    user.onboarded? ? redirect_to(settings_path, notice: "HEY is connected.") : redirect_to(onboarding_path(step: 4))
  rescue HeyClient::AuthError => e
    Rails.logger.warn("HEY OAuth exchange error: #{e.message}")
    session[:user_id] = user.id if user && expected_user.nil?
    redirect_after_hey_failure("Couldn't connect HEY. Want to try again?")
  end

  def loopback_request?
    LOOPBACK_HOSTS.include?(request.host.to_s.delete_prefix("[").delete_suffix("]"))
  end

  def hey_oauth_cache_key(state)
    "hey_oauth/v1/#{Digest::SHA256.hexdigest(state.to_s)}"
  end

  def redirect_after_hey_failure(message)
    logged_in? ? redirect_to(settings_path, alert: message) : redirect_to(login_path, alert: message)
  end
end
