# One-time code that carries a sign-in from the system browser back into a
# native app. The browser finishes Basecamp OAuth, gets a code that lives for
# two minutes, and hands it to the app through a daybreak:// link; the app's
# web view trades it for its own session.
#
# Any app can claim daybreak:// links, so the code alone is not enough. The app
# makes a secret (the verifier), starts sign-in with its SHA-256 (the challenge),
# and has to show the verifier to redeem the code (PKCE, RFC 7636 and 8252).
module NativeSignIn
  EXPIRES_IN = 2.minutes
  CHALLENGE_FORMAT = /\A[A-Za-z0-9_-]{43}\z/

  module_function

  def valid_challenge?(challenge)
    CHALLENGE_FORMAT.match?(challenge.to_s)
  end

  def challenge_for(verifier)
    Base64.urlsafe_encode64(Digest::SHA256.digest(verifier.to_s), padding: false)
  end

  def issue(user, challenge)
    data = { "user_id" => user.id, "challenge" => challenge, "nonce" => SecureRandom.hex(16) }
    message_verifier.generate(data, expires_in: EXPIRES_IN, purpose: :native_sign_in)
  end

  # The user the code was issued for, or nil if it is forged, expired, already
  # used, or the verifier doesn't match the challenge it was issued with.
  def redeem(code, verifier)
    data = message_verifier.verified(code.to_s, purpose: :native_sign_in)
    return unless data.is_a?(Hash) && verifier.present?
    return unless ActiveSupport::SecurityUtils.secure_compare(challenge_for(verifier), data["challenge"].to_s)
    return unless Rails.cache.write("native_sign_in/#{data["nonce"]}", true, expires_in: EXPIRES_IN, unless_exist: true)

    User.find_by(id: data["user_id"])
  end

  def app_url(user, challenge)
    "daybreak://signed-in?code=#{CGI.escape(issue(user, challenge))}"
  end

  def message_verifier
    Rails.application.message_verifier(:native_sign_in)
  end
end
