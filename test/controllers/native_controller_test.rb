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

  test "sign in trades a code for a session" do
    get native_sign_in_path(code: NativeSignIn.issue(users(:one)))

    assert_redirected_to root_path
    follow_redirect!
    assert_response :success
  end

  test "sign in refuses a forged code" do
    get native_sign_in_path(code: "nope")

    assert_redirected_to login_path
  end

  test "a code works once" do
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    code = NativeSignIn.issue(users(:one))

    assert_equal users(:one), NativeSignIn.redeem(code)
    assert_nil NativeSignIn.redeem(code)
  ensure
    Rails.cache = original
  end

  test "a code expires" do
    code = NativeSignIn.issue(users(:one))

    travel NativeSignIn::EXPIRES_IN + 1.second do
      assert_nil NativeSignIn.redeem(code)
    end
  end
end
