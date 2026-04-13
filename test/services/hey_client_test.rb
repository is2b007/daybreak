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

  test "calendars returns [] for nil API response" do
    client = HeyClient.new(@user)
    client.define_singleton_method(:get) { |_path| nil }

    assert_equal [], client.calendars
  end

  test "calendar_id_for_timed_writes prefers default then personal calendar" do
    @user.update_column(:hey_default_calendar_id, "cal-explicit")
    client = HeyClient.new(@user)
    assert_equal "cal-explicit", client.calendar_id_for_timed_writes

    @user.update_column(:hey_default_calendar_id, nil)
    client = HeyClient.new(@user)
    wrapped = {
      "calendars" => [
        { "calendar" => { "id" => 7, "name" => "Work", "personal" => false } },
        { "calendar" => { "id" => 1, "name" => "Personal", "personal" => true } }
      ]
    }
    client.define_singleton_method(:get) { |path| path == "/calendars.json" ? wrapped : nil }

    assert_equal "1", client.calendar_id_for_timed_writes
  end

  test "calendars unwraps hey-sdk CalendarListPayload shape" do
    client = HeyClient.new(@user)
    wrapped = {
      "calendars" => [
        { "calendar" => { "id" => 7, "name" => "Work", "personal" => false } },
        { "calendar" => { "id" => 1, "name" => "Personal", "personal" => true } }
      ]
    }
    client.define_singleton_method(:get) { |path| path == "/calendars.json" ? wrapped : nil }

    rows = client.calendars
    assert_equal 2, rows.size
    assert_equal "7", rows.first["id"]
    assert_equal "Work", rows.first["name"]
    assert_equal "1", rows.last["id"]
    assert_equal true, rows.last["personal"]
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

  test "calendar_events unwraps wrapped calendars.json then fetches recordings" do
    client = HeyClient.new(@user)
    paths = []
    wrapped = {
      "calendars" => [
        { "calendar" => { "id" => 42, "name" => "Personal", "personal" => true } }
      ]
    }
    client.define_singleton_method(:get) do |path|
      paths << path
      case path.to_s
      when "/calendars.json"
        wrapped
      when /\A\/calendars\/42\/recordings\.json/
        {
          "Calendar::Event" => [
            { "id" => 9, "title" => "Meet", "starts_at" => "2026-04-10T14:00:00Z", "ends_at" => "2026-04-10T15:00:00Z" }
          ]
        }
      else
        nil
      end
    end

    rows = client.calendar_events(starts_on: "2026-04-08", ends_on: "2026-04-14")
    assert_equal 1, rows.size
    assert_equal "9", rows.first["id"]
    assert_includes paths, "/calendars.json"
    assert(paths.any? { |p| p.start_with?("/calendars/42/recordings.json") })
  end

  test "todos lists Calendar::Todo from personal calendar recordings" do
    client = HeyClient.new(@user)
    paths = []
    wrapped = {
      "calendars" => [
        { "calendar" => { "id" => 99, "name" => "Other", "personal" => false } },
        { "calendar" => { "id" => 42, "name" => "Personal", "personal" => true } }
      ]
    }
    client.define_singleton_method(:get) do |path|
      paths << path
      case path.to_s
      when "/calendars.json"
        wrapped
      when /\A\/calendars\/42\/recordings\.json/
        {
          "Calendar::Todo" => [
            { "id" => 100, "title" => "Buy milk", "starts_at" => "2026-04-10T09:00:00Z", "completed_at" => nil },
            { "id" => 101, "title" => "Done task", "starts_at" => "2026-04-11T10:00:00Z", "completed_at" => "2026-04-11T11:00:00Z" }
          ]
        }
      else
        nil
      end
    end

    rows = client.todos
    assert_equal 2, rows.size
    assert_equal "100", rows[0]["id"]
    assert_equal "Buy milk", rows[0]["title"]
    assert_equal false, rows[0]["completed"]
    assert_equal "101", rows[1]["id"]
    assert_equal true, rows[1]["completed"]
    assert(paths.any? { |p| p.start_with?("/calendars/42/recordings.json") })
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
