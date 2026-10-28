class NativeController < ApplicationController
  skip_before_action :authenticate_user!
  skip_before_action :require_onboarding!

  # The apps call this when someone types a server address, to check it is a
  # Daybreak and learn where to sign in.
  def server
    # The desktop app's setup page asks from its own origin.
    response.headers["Access-Control-Allow-Origin"] = "*"
    render json: {
      app: "daybreak",
      name: "Daybreak",
      version: Rails.root.join("VERSION").read.strip,
      sign_in_url: auth_basecamp_url(native: 1),
      path_configuration_url: native_path_configuration_url
    }
  end

  # Hotwire Native Android: which screens open as sheets, and where pull to refresh is on.
  def path_configuration
    render json: {
      settings: {},
      rules: [
        {
          patterns: [ ".*" ],
          properties: { context: "default", uri: "hotwire://fragment/web", pull_to_refresh_enabled: true }
        },
        {
          patterns: [ "^$", "^/$" ],
          properties: { presentation: "clear_all" }
        },
        {
          patterns: [ "/new$", "/edit$" ],
          properties: { context: "modal", uri: "hotwire://fragment/web/modal/sheet", pull_to_refresh_enabled: false }
        },
        {
          patterns: [ "^/ritual/", "^/onboarding" ],
          properties: { pull_to_refresh_enabled: false }
        }
      ]
    }
  end

  # The app's web view lands here with the code from the daybreak:// link.
  def sign_in
    user = NativeSignIn.redeem(params[:code])
    unless user
      redirect_to login_path, alert: "That sign-in took too long. Want to try again?"
      return
    end

    reset_session
    session[:user_id] = user.id
    redirect_to user.onboarded? ? root_path : onboarding_path
  end
end
