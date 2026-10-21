require "test_helper"

# A 401 used to send the clients round refresh_and_retry! forever whenever the stored
# expiry was still ahead: the refresh was skipped as "fresh" and the dead token resent.
class TokenRefreshTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
  end

  test "HEY retries a 401 once after refreshing, then succeeds" do
    connect_hey(expires_at: 1.week.from_now)
    client = HeyClient.new(@user)
    sent = []
    stub_http(client, sent, [ response(401), response(200, '{"calendars":[]}') ])

    with_class_stub(HeyClient, :refresh_token, ->(_rt) { { "access_token" => "new-a", "refresh_token" => "new-r", "expires_in" => 3600 } }) do
      assert_equal [], client.calendars
    end

    assert_equal [ "Bearer old-a", "Bearer new-a" ], sent
    assert_equal "new-r", @user.reload.hey_refresh_token
  end

  test "HEY gives up after one retry instead of looping on a persistent 401" do
    connect_hey(expires_at: 1.week.from_now)
    client = HeyClient.new(@user)
    sent = []
    stub_http(client, sent, Array.new(10) { response(401) })

    with_class_stub(HeyClient, :refresh_token, ->(_rt) { { "access_token" => "new-a", "expires_in" => 3600 } }) do
      assert_raises(HeyClient::AuthError) { client.calendars }
    end

    assert_equal 2, sent.size
  end

  test "HEY marks itself disconnected when the refresh token is refused" do
    connect_hey(expires_at: 1.week.from_now)
    client = HeyClient.new(@user)
    sent = []
    stub_http(client, sent, Array.new(10) { response(401) })

    refused = ->(_rt) { raise HeyClient::RefreshRefused, "invalid_grant" }
    with_class_stub(HeyClient, :refresh_token, refused) do
      assert_raises(HeyClient::AuthError) { client.calendars }
    end

    assert_equal 1, sent.size
    refute @user.reload.hey_connected?
    assert_nil @user.hey_refresh_token
  end

  test "HEY keeps credentials when the token endpoint fails for another reason" do
    connect_hey(expires_at: 1.week.from_now)
    client = HeyClient.new(@user)
    stub_http(client, [], Array.new(10) { response(401) })

    outage = ->(_rt) { raise HeyClient::AuthError, "HEY token refresh failed: 503" }
    with_class_stub(HeyClient, :refresh_token, outage) do
      assert_raises(HeyClient::AuthError) { client.calendars }
    end

    assert @user.reload.hey_connected?
    assert_equal "old-r", @user.hey_refresh_token
  end

  test "a pasted HEY token is sent past its guessed expiry and dropped once HEY refuses it" do
    connect_hey(expires_at: 1.day.ago, refresh_token: nil)
    client = HeyClient.new(@user)
    sent = []
    stub_http(client, sent, [ response(401) ])

    assert_raises(HeyClient::AuthError) { client.calendars }

    assert_equal [ "Bearer old-a" ], sent
    refute @user.reload.hey_connected?
  end

  test "refresh_refused? only trusts invalid_grant" do
    assert HeyClient.refresh_refused?(response(400, '{"error":"invalid_grant"}'))
    refute HeyClient.refresh_refused?(response(400, '{"error":"invalid_request"}'))
    refute HeyClient.refresh_refused?(response(503, '{"error":"invalid_grant"}'))
    refute HeyClient.refresh_refused?(response(401, "not json"))
  end

  test "HEY todos without a personal calendar does not report a complete read" do
    connect_hey(expires_at: 1.week.from_now)
    client = HeyClient.new(@user)
    cals = { "calendars" => [ { "calendar" => { "id" => 7, "name" => "Work", "personal" => false } } ] }
    client.define_singleton_method(:get) { |path, **| path == "/calendars.json" ? cals : nil }

    assert_equal [], client.todos
    refute client.recordings_complete?
  end

  test "Basecamp gives up after one retry instead of looping on a persistent 401" do
    @user.update!(
      basecamp_access_token: "old-a",
      basecamp_refresh_token: "old-r",
      basecamp_token_expires_at: 1.week.from_now,
      basecamp_account_id: "123"
    )
    client = BasecampClient.new(@user)
    sent = []
    stub_http(client, sent, Array.new(10) { response(401) })

    with_class_stub(BasecampClient, :refresh_token, ->(_rt) { { "access_token" => "new-a", "expires_in" => 3600 } }) do
      assert_raises(BasecampClient::AuthError) { client.my_profile }
    end

    assert_equal [ "Bearer old-a", "Bearer new-a" ], sent
  end

  test "RefreshTokensJob renews soon-to-expire HEY tokens through the client" do
    connect_hey(expires_at: 1.day.from_now)
    calls = 0
    renew = ->(rt) { calls += 1; assert_equal "old-r", rt; { "access_token" => "new-a", "refresh_token" => "new-r", "expires_in" => 1209600 } }

    with_class_stub(HeyClient, :refresh_token, renew) do
      RefreshTokensJob.perform_now
    end

    assert_equal 1, calls
    assert_equal "new-a", @user.reload.hey_access_token
    assert @user.hey_token_expires_at > 1.week.from_now
  end

  private

  def connect_hey(expires_at:, refresh_token: "old-r")
    @user.update!(hey_access_token: "old-a", hey_refresh_token: refresh_token, hey_token_expires_at: expires_at)
  end

  def response(code, body = "")
    klass = Net::HTTPResponse::CODE_TO_OBJ[code.to_s]
    res = klass.new("1.1", code.to_s, "")
    res.instance_variable_set(:@read, true)
    res.instance_variable_set(:@body, body)
    res
  end

  # Serves +responses+ in order and records the Authorization header of each request.
  def stub_http(client, sent, responses)
    queue = responses.dup
    client.define_singleton_method(:http_start) do |_uri, &block|
      fake = Object.new
      fake.define_singleton_method(:request) do |req|
        sent << req["Authorization"]
        queue.shift || raise("unexpected extra request")
      end
      block.call(fake)
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
