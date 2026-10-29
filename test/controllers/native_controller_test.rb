require "test_helper"

class NativeControllerTest < ActionDispatch::IntegrationTest
  test "config tells an app this is a Daybreak and where to sign in" do
    get native_config_path

    assert_response :success
    body = response.parsed_body
    assert_equal "daybreak", body["app"]
    assert_equal Rails.root.join("VERSION").read.strip, body["version"]
    assert_match %r{/auth/basecamp\?native=1\z}, body["sign_in_url"]
  end

  test "path configuration opens new and edit screens as sheets" do
    get native_path_configuration_path

    assert_response :success
    modal = response.parsed_body["rules"].find { |rule| rule["properties"]["context"] == "modal" }
    assert_includes modal["patterns"], "/new$"
  end

  APP = { "User-Agent" => "Daybreak Android; Hotwire Native Android; Turbo Native Android" }
  VERIFIER = "a" * 43
  CHALLENGE = NativeSignIn.challenge_for(VERIFIER)

  test "sign in trades a code and its verifier for a session" do
    get native_sign_in_path(code: NativeSignIn.issue(users(:one), CHALLENGE), verifier: VERIFIER), headers: APP

    assert_redirected_to root_path
    follow_redirect! headers: APP
    assert_response :success
  end

  test "sign in refuses a forged code" do
    get native_sign_in_path(code: "nope", verifier: VERIFIER), headers: APP

    assert_redirected_to login_path
  end

  test "sign in refuses a code without the app's verifier" do
    code = NativeSignIn.issue(users(:one), CHALLENGE)

    get native_sign_in_path(code: code), headers: APP
    assert_redirected_to login_path

    get native_sign_in_path(code: code, verifier: "b" * 43), headers: APP
    assert_redirected_to login_path
  end

  test "sign in only works in the apps" do
    get native_sign_in_path(code: NativeSignIn.issue(users(:one), CHALLENGE), verifier: VERIFIER)

    assert_redirected_to login_path
  end

  test "app sessions last a year" do
    get native_sign_in_path(code: NativeSignIn.issue(users(:one), CHALLENGE), verifier: VERIFIER), headers: APP

    assert_match(/expires=/i, response.headers["Set-Cookie"].to_s)
  end

  test "browser sessions end with the browser" do
    get login_path

    assert_no_match(/expires=/i, response.headers["Set-Cookie"].to_s)
  end

  test "handoff asks before sending the session to the app" do
    sign_in_with_challenge

    get native_handoff_path
    assert_response :success
    assert_select "form[action=?][method=post]", native_handoff_path

    post native_handoff_path
    assert_match %r{\Adaybreak://signed-in\?code=}, response.location
    code = CGI.unescape(response.location[/code=(.+)\z/, 1])
    assert_equal users(:one), NativeSignIn.redeem(code, VERIFIER)
  end

  test "handoff needs a sign-in started by an app" do
    get native_handoff_path
    assert_redirected_to login_path

    post native_handoff_path
    assert_redirected_to login_path
  end

  test "a code works once" do
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    code = NativeSignIn.issue(users(:one), CHALLENGE)

    assert_equal users(:one), NativeSignIn.redeem(code, VERIFIER)
    assert_nil NativeSignIn.redeem(code, VERIFIER)
  ensure
    Rails.cache = original
  end

  test "a code expires" do
    code = NativeSignIn.issue(users(:one), CHALLENGE)

    travel NativeSignIn::EXPIRES_IN + 1.second do
      assert_nil NativeSignIn.redeem(code, VERIFIER)
    end
  end

  private

  # Signs in through the app's native sign-in, which leaves the challenge in the browser session.
  def sign_in_with_challenge
    get native_sign_in_path(code: NativeSignIn.issue(users(:one), CHALLENGE), verifier: VERIFIER), headers: APP
    get auth_basecamp_path(native: 1, code_challenge: CHALLENGE)
    assert_redirected_to native_handoff_path
  end
end
