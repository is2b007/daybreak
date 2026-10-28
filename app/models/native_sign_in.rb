# One-time code that carries a sign-in from the system browser back into a
# native app. The browser finishes Basecamp OAuth, gets a code that lives for
# two minutes, and hands it to the app through a daybreak:// link; the app's
# web view trades it for its own session.
module NativeSignIn
  EXPIRES_IN = 2.minutes

  module_function

  def issue(user)
    verifier.generate({ "user_id" => user.id, "nonce" => SecureRandom.hex(16) }, expires_in: EXPIRES_IN, purpose: :native_sign_in)
  end

  # The user the code was issued for, or nil if it is forged, expired or already used.
  def redeem(code)
    data = verifier.verified(code.to_s, purpose: :native_sign_in)
    return unless data.is_a?(Hash)
    return unless Rails.cache.write("native_sign_in/#{data["nonce"]}", true, expires_in: EXPIRES_IN, unless_exist: true)

    User.find_by(id: data["user_id"])
  end

  def app_url(user)
    "daybreak://signed-in?code=#{CGI.escape(issue(user))}"
  end

  def verifier
    Rails.application.message_verifier(:native_sign_in)
  end
end
