require "test_helper"

class HeyClientTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @user.update!(
      hey_access_token: "stub-token",
      hey_refresh_token: "stub-refresh",
      hey_token_expires_at: 2.weeks.from_now
    )
  end

  test "write_journal sends calendar_journal_entry envelope per HEY API" do
    client = HeyClient.new(@user)
    captured = nil
    client.define_singleton_method(:request) do |method, path, body|
      captured = { method: method, path: path, body: body }
      {}
    end

    client.write_journal("2026-04-10", "Line one")

    assert captured
    assert_equal :patch, captured[:method]
    assert_equal "/calendar/days/2026-04-10/journal_entry.json", captured[:path]
    assert_equal(
      { "calendar_journal_entry" => { "content" => "Line one" } },
      captured[:body]
    )
  end
end
