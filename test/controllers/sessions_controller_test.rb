require "test_helper"

class SessionsControllerTest < ActionController::TestCase
  IDENTITY = {
    "identity" => { "id" => 4242, "first_name" => "New", "email_address" => "new@example.com" },
    "accounts" => []
  }.freeze

  setup do
    @prev_client_id = ENV["BASECAMP_CLIENT_ID"]
    @prev_allowed = ENV[SessionsController::ALLOWED_IDS_ENV]
    ENV["BASECAMP_CLIENT_ID"] = "client"
    ENV.delete(SessionsController::ALLOWED_IDS_ENV)
  end

  teardown do
    ENV["BASECAMP_CLIENT_ID"] = @prev_client_id
    ENV[SessionsController::ALLOWED_IDS_ENV] = @prev_allowed
  end

  test "new sends a fresh state to Basecamp" do
    get :new

    assert_response :success
    url = CGI.unescapeHTML(response.body[%r{href="(https://launchpad\.37signals\.com/authorization/new[^"]+)"}, 1])
    state = Rack::Utils.parse_query(URI.parse(url).query)["state"]
    assert state.present?
    assert_equal session[:basecamp_oauth_state], state
  end

  test "create refuses a callback whose state we did not issue" do
    session[:basecamp_oauth_state] = "ours"

    with_basecamp_sign_in(IDENTITY) { get :create, params: { code: "c", state: "theirs" } }

    assert_redirected_to login_path
    assert_nil session[:user_id]
    assert_nil session[:basecamp_oauth_state]
  end

  test "create refuses a stranger once the install has an owner" do
    session[:basecamp_oauth_state] = "s"

    assert_no_difference -> { User.count } do
      with_basecamp_sign_in(IDENTITY) { get :create, params: { code: "c", state: "s" } }
    end

    assert_redirected_to login_path
    assert_match(/belongs to someone else/, flash[:alert])
  end

  test "create lets in identities listed in the allowlist" do
    ENV[SessionsController::ALLOWED_IDS_ENV] = "1, 4242"
    session[:basecamp_oauth_state] = "s"

    with_basecamp_sign_in(IDENTITY) { get :create, params: { code: "c", state: "s" } }

    user = User.find_by!(basecamp_uid: "4242")
    assert_equal user.id, session[:user_id]
  end

  test "create lets the existing owner back in" do
    owner = users(:one)
    session[:basecamp_oauth_state] = "s"
    identity = IDENTITY.merge("identity" => IDENTITY["identity"].merge("id" => owner.basecamp_uid))

    with_basecamp_sign_in(identity) { get :create, params: { code: "c", state: "s" } }

    assert_equal owner.id, session[:user_id]
  end

  CHALLENGE = NativeSignIn.challenge_for("a" * 43)

  test "a native sign-in goes straight to Basecamp" do
    get :new, params: { native: 1, code_challenge: CHALLENGE }

    assert_redirected_to %r{\Ahttps://launchpad\.37signals\.com/authorization/new}
    assert_equal CHALLENGE, session[:native_sign_in]
  end

  test "a native sign-in without a challenge is a plain web sign-in" do
    get :new, params: { native: 1 }

    assert_response :success
    assert_nil session[:native_sign_in]
  end

  test "a native sign-in hands the session back to the app" do
    owner = users(:one)
    session[:basecamp_oauth_state] = "s"
    session[:native_sign_in] = CHALLENGE
    identity = IDENTITY.merge("identity" => IDENTITY["identity"].merge("id" => owner.basecamp_uid))

    with_basecamp_sign_in(identity) { get :create, params: { code: "c", state: "s" } }

    assert_redirected_to native_handoff_path
    assert_equal CHALLENGE, session[:native_sign_in]
  end

  test "a native sign-in from an already signed-in browser asks first" do
    session[:user_id] = users(:one).id

    get :new, params: { native: 1, code_challenge: CHALLENGE }

    assert_redirected_to native_handoff_path
  end

  private

  def with_basecamp_sign_in(identity)
    tokens = { "access_token" => "a", "refresh_token" => "r", "expires_in" => 3600 }
    with_class_stub(BasecampClient, :exchange_code, ->(*) { tokens }) do
      with_class_stub(BasecampClient, :fetch_identity, ->(*) { identity }) do
        with_class_stub(SyncBasecampAssignmentsJob, :perform_now, ->(*) { nil }) do
          yield
        end
      end
    end
  end

  def with_class_stub(klass, name, impl)
    original = klass.method(name)
    klass.define_singleton_method(name) { |*args, **kw| impl.call(*args, **kw) }
    yield
  ensure
    klass.singleton_class.send(:remove_method, name)
    klass.define_singleton_method(name, original)
  end
end
