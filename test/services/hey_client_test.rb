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

  test "calendar_events fetches recordings.json with date range per calendar" do
    client = HeyClient.new(@user)
    paths = []

    client.define_singleton_method(:get) do |path|
      paths << path
      case path.to_s
      when "/calendars.json"
        [ { "id" => 42, "name" => "Personal" } ]
      when /\A\/calendars\/42\/recordings\.json/
        {
          "Calendar::Event" => [
            { "id" => 9, "title" => "A", "starts_at" => "2026-04-10T14:00:00Z", "ends_at" => "2026-04-10T15:00:00Z" }
          ]
        }
      else
        []
      end
    end

    rows = client.calendar_events(starts_on: "2026-04-08", ends_on: "2026-04-14")
    assert_equal 1, rows.size
    assert_equal "9", rows.first["id"]
    assert_equal "42", rows.first["hey_calendar_id"]
    assert_includes paths.join(" "), "/calendars/42/recordings.json"
    assert_includes paths.join(" "), "starts_on=2026-04-08"
    assert_includes paths.join(" "), "ends_on=2026-04-14"
  end

  test "flatten_calendar_recordings dedupes by calendar and id" do
    client = HeyClient.new(@user)
    raw = {
      "Calendar::Event" => [
        { "id" => 1, "title" => "X", "starts_at" => "2026-04-10T10:00:00Z" }
      ],
      "Calendar::Todo" => [
        { "id" => 2, "title" => "Y", "starts_at" => "2026-04-10T11:00:00Z" }
      ]
    }
    rows = client.send(:flatten_calendar_recordings, raw, calendar_id: "c1")
    assert_equal 2, rows.size
    assert_equal %w[1 2], rows.map { |r| r["id"] }.sort
  end
end
