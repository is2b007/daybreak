module Authentication
  extend ActiveSupport::Concern

  included do
    helper_method :current_user, :logged_in?, :native_app?
    before_action :keep_native_sessions
  end

  private

  def current_user
    @current_user ||= User.find_by(id: session[:user_id]) if session[:user_id]
  end

  def logged_in?
    current_user.present?
  end

  # The Android app (Hotwire Native) and the desktop app (Tauri) both say so in
  # their user agent. They sign in through the system browser, not the web view.
  def native_app?
    request.user_agent.to_s.match?(/Hotwire Native|Daybreak Desktop/)
  end

  # App web views can drop cookies that end with the browser session, so the
  # apps get one that lasts a year. Browsers keep the usual session cookie.
  def keep_native_sessions
    request.session_options[:expire_after] = 1.year if native_app?
  end

  def authenticate_user!
    unless logged_in?
      redirect_to login_path, alert: "Sign in to pick up where you left off."
    end
  end

  def require_onboarding!
    if logged_in? && !current_user.onboarded?
      redirect_to onboarding_path unless controller_name == "onboarding"
    end
  end
end
