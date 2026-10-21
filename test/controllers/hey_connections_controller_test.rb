require "test_helper"

class HeyConnectionsControllerTest < ActionController::TestCase
  UUID_V4 = /\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/

  setup do
    @user = users(:one)
    session[:user_id] = @user.id
    @prev_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  teardown do
    Rails.cache = @prev_cache
  end

  test "new explains pasted CLI tokens cannot refresh" do
    get :new

    assert_response :success
    assert_match(/cannot refresh/i, response.body)
    assert_match(/two weeks/i, response.body)
  end

  test "new is reachable during onboarding" do
    @user.update!(onboarded: false)

    get :new

    assert_response :success
  end

  test "authorize on a local install redirects straight to HEY with a fresh install id" do
    request.host = "localhost"

    get :authorize

    assert_response :redirect
    query = Rack::Utils.parse_query(URI.parse(response.location).query)
    assert_equal "http://127.0.0.1/auth/hey/callback", query["redirect_uri"].sub(/:\d+/, "")
    assert_match UUID_V4, query["install_id"]
  end

  test "authorize on a hosted install renders the paste step" do
    request.host = "daybreak.example.com"

    get :authorize

    assert_response :success
    assert_match(/Paste the address you land on/, response.body)
    url = response.body[/href="(https:\/\/app\.hey\.com\/oauth\/authorizations\/new[^"]+)"/, 1]
    query = Rack::Utils.parse_query(URI.parse(CGI.unescapeHTML(url)).query)
    assert_equal "http://127.0.0.1:#{HeyConnectionsController::PASTE_REDIRECT_PORT}/auth/hey/callback", query["redirect_uri"]
  end

  test "authorize reuses the install id the user already has" do
    @user.update!(hey_install_id: "1b4e28ba-2fa1-41d2-883f-0016d3cca427")
    request.host = "localhost"

    get :authorize

    query = Rack::Utils.parse_query(URI.parse(response.location).query)
    assert_equal "1b4e28ba-2fa1-41d2-883f-0016d3cca427", query["install_id"]
  end

  test "complete exchanges the pasted address and stores the install id" do
    @user.update!(hey_reconnect_needed_at: 1.day.ago)
    state = start_hosted_flow
    captured = nil
    exchange = lambda do |code, redirect_uri, code_verifier:, install_id:|
      captured = { code: code, redirect_uri: redirect_uri, verifier: code_verifier, install_id: install_id }
      { "access_token" => "a", "refresh_token" => "r", "expires_in" => 3600 }
    end

    with_class_stub(HeyClient, :exchange_code, exchange) do
      post :complete, params: { callback_url: "http://127.0.0.1:47823/auth/hey/callback?code=abc&state=#{state}" }
    end

    assert_redirected_to settings_path
    assert_equal "abc", captured[:code]
    assert_equal "http://127.0.0.1:47823/auth/hey/callback", captured[:redirect_uri]
    assert captured[:verifier].present?
    @user.reload
    assert_equal captured[:install_id], @user.hey_install_id
    assert_match UUID_V4, @user.hey_install_id
    assert_equal "r", @user.hey_refresh_token
    assert_nil @user.hey_reconnect_needed_at
  end

  test "complete rejects an address without a code" do
    post :complete, params: { callback_url: "https://example.com/nothing" }

    assert_redirected_to auth_hey_path
    assert_match(/didn't come from HEY/, flash[:alert])
  end

  test "complete refuses a state started by another user" do
    state = start_hosted_flow
    session[:user_id] = users(:two).id

    post :complete, params: { callback_url: "http://127.0.0.1:47823/auth/hey/callback?code=abc&state=#{state}" }

    assert_redirected_to settings_path
    refute users(:two).reload.hey_connected?
  end

  test "complete passes HEY's cancellation through" do
    post :complete, params: { callback_url: "http://127.0.0.1:47823/auth/hey/callback?error=access_denied&error_description=Denied" }

    assert_redirected_to auth_hey_path
    assert_equal "Denied", flash[:alert]
  end

  private

  def start_hosted_flow
    request.host = "daybreak.example.com"
    get :authorize
    url = CGI.unescapeHTML(response.body[/href="(https:\/\/app\.hey\.com[^"]+)"/, 1])
    Rack::Utils.parse_query(URI.parse(url).query)["state"]
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
