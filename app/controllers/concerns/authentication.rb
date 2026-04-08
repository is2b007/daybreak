module Authentication
  extend ActiveSupport::Concern

  included do
    helper_method :current_user, :logged_in?
  end

  private

  def current_user
    @current_user ||= User.find_by(id: session[:user_id]) if session[:user_id]
  end

  def logged_in?
    current_user.present?
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
