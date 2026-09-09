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
    client.define_singleton_method(:request) do |method, path, body = nil, allow: []|
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

  test "create_todo sends bare YYYY-MM-DD on calendar_todo" do
    client = HeyClient.new(@user)
    captured = nil
    client.define_singleton_method(:request) do |method, path, body = nil, allow: []|
      captured = { method: method, path: path, body: body }
      { "id" => 12 }
    end

    client.create_todo(title: "Buy milk", starts_at: Date.new(2026, 4, 19))

    assert_equal :post, captured[:method]
    assert_equal "/calendar/todos.json", captured[:path]
    assert_equal(
      { "calendar_todo" => { title: "Buy milk", starts_at: "2026-04-19" } },
      captured[:body]
    )
  end

  test "update_todo patches official todos.json path and omits empty fields" do
    client = HeyClient.new(@user)
    captured = nil
    client.define_singleton_method(:request) do |method, path, body = nil, allow: []|
      captured = { method: method, path: path, body: body }
      {}
    end

    client.update_todo("77", title: "Renamed")

    assert_equal :patch, captured[:method]
    assert_equal "/calendar/todos/77.json", captured[:path]
    assert_equal({ "calendar_todo" => { title: "Renamed" } }, captured[:body])
  end

  test "delete_todo uses .json suffix" do
    client = HeyClient.new(@user)
    captured = nil
    client.define_singleton_method(:request) do |method, path, body = nil, allow: []|
      captured = { method: method, path: path }
      {}
    end

    client.delete_todo("9")

    assert_equal :delete, captured[:method]
    assert_equal "/calendar/todos/9.json", captured[:path]
  end

  test "create_timed_calendar_event_form posts /calendar/events.json with set_time_zone" do
    client = HeyClient.new(@user)
    captured = nil
    client.define_singleton_method(:form_request) do |method, path, pairs|
      captured = { method: method, path: path, pairs: pairs }
      { code: 201, body: { "id" => 55 }.to_json, location: nil, unauthorized: false, success: true }
    end

    zone = ActiveSupport::TimeZone["America/Los_Angeles"]
    id = client.create_timed_calendar_event_form(
      calendar_id: "42",
      title: "Focus",
      local_start: zone.local(2026, 4, 13, 14, 0),
      local_end: zone.local(2026, 4, 13, 15, 0),
      time_zone: "America/Los_Angeles"
    )

    assert_equal "55", id
    assert_equal :post, captured[:method]
    assert_equal "/calendar/events.json", captured[:path]
    assert_includes captured[:pairs], [ "calendar_event[set_time_zone]", "1" ]
    assert_includes captured[:pairs], [ "calendar_event[starts_at_time_zone_name]", "America/Los_Angeles" ]
    assert_includes captured[:pairs], [ "calendar_event[starts_at]", "2026-04-13" ]
    assert_includes captured[:pairs], [ "calendar_event[starts_at_time]", "14:00:00" ]
  end

  test "create_timed_calendar_event_form falls back to redirect id" do
    client = HeyClient.new(@user)
    client.define_singleton_method(:form_request) do |_method, _path, _pairs|
      { code: 302, body: "", location: "/calendar/events/99", unauthorized: false, success: true }
    end

    zone = ActiveSupport::TimeZone["UTC"]
    id = client.create_timed_calendar_event_form(
      calendar_id: "1",
      title: "X",
      local_start: zone.local(2026, 4, 13, 10, 0),
      local_end: zone.local(2026, 4, 13, 11, 0),
      time_zone: "UTC"
    )

    assert_equal "99", id
  end

  test "update_calendar_event patches official events.json path" do
    client = HeyClient.new(@user)
    captured = nil
    client.define_singleton_method(:form_request) do |method, path, pairs|
      captured = { method: method, path: path, pairs: pairs }
      { code: 200, body: { "id" => 8 }.to_json, location: nil, unauthorized: false, success: true }
    end

    zone = ActiveSupport::TimeZone["UTC"]
    id = client.update_calendar_event(
      calendar_id: "3",
      event_id: "8",
      title: "Meet",
      starts_at: zone.local(2026, 4, 13, 9, 0),
      ends_at: zone.local(2026, 4, 13, 10, 0),
      all_day: false,
      time_zone: "UTC"
    )

    assert_equal "8", id
    assert_equal :patch, captured[:method]
    assert_equal "/calendar/events/8.json", captured[:path]
    assert_includes captured[:pairs], [ "calendar_event[set_time_zone]", "1" ]
    assert_includes captured[:pairs], [ "calendar_event[description]", "" ]
    assert_includes captured[:pairs], [ "calendar_event[location]", "" ]
    assert_includes captured[:pairs], [ "calendar_event[url]", "" ]
    assert_includes captured[:pairs], [ "calendar_event[entry_id]", "" ]
  end

  test "update_calendar_event echoes stored description location url and entry_id" do
    client = HeyClient.new(@user)
    captured = nil
    client.define_singleton_method(:form_request) do |method, path, pairs|
      captured = { method: method, path: path, pairs: pairs }
      { code: 200, body: { "id" => 8 }.to_json, location: nil, unauthorized: false, success: true }
    end

    zone = ActiveSupport::TimeZone["UTC"]
    client.update_calendar_event(
      calendar_id: "3",
      event_id: "8",
      title: "Meet",
      starts_at: zone.local(2026, 4, 13, 9, 0),
      ends_at: zone.local(2026, 4, 13, 10, 0),
      all_day: false,
      time_zone: "UTC",
      description: "Bring slides",
      location: "Room 4",
      url: "https://meet.example.com/x",
      entry_id: "55"
    )

    assert_includes captured[:pairs], [ "calendar_event[description]", "Bring slides" ]
    assert_includes captured[:pairs], [ "calendar_event[location]", "Room 4" ]
    assert_includes captured[:pairs], [ "calendar_event[url]", "https://meet.example.com/x" ]
    assert_includes captured[:pairs], [ "calendar_event[entry_id]", "55" ]
    assert_equal false, captured[:pairs].any? { |k, _| k == "apply_to_future" }
  end

  test "update_calendar_event routes occurrence ids to occurrences endpoint" do
    client = HeyClient.new(@user)
    captured = nil
    client.define_singleton_method(:form_request) do |method, path, pairs|
      captured = { method: method, path: path, pairs: pairs }
      { code: 200, body: { "id" => 88 }.to_json, location: nil, unauthorized: false, success: true }
    end

    zone = ActiveSupport::TimeZone["UTC"]
    client.update_calendar_event(
      calendar_id: "3",
      event_id: "88:2026-04-15",
      title: "Weekly",
      starts_at: zone.local(2026, 4, 15, 9, 0),
      ends_at: zone.local(2026, 4, 15, 10, 0),
      all_day: false,
      time_zone: "UTC"
    )

    assert_equal "/calendar/events/88/occurrences/2026-04-15.json", captured[:path]
    assert_includes captured[:pairs], [ "apply_to_future", "0" ]
    assert_includes captured[:pairs], [ "repeat_frequency", "custom" ]
  end

  test "update_calendar_event accepts official underscore occurrence_id" do
    client = HeyClient.new(@user)
    captured = nil
    client.define_singleton_method(:form_request) do |_method, path, pairs|
      captured = { path: path, pairs: pairs }
      { code: 200, body: { "id" => 88 }.to_json, location: nil, unauthorized: false, success: true }
    end

    zone = ActiveSupport::TimeZone["UTC"]
    client.update_calendar_event(
      calendar_id: "3",
      event_id: "88_2026-04-15",
      title: "Weekly",
      starts_at: zone.local(2026, 4, 15, 9, 0),
      ends_at: zone.local(2026, 4, 15, 10, 0),
      all_day: false,
      time_zone: "UTC"
    )

    assert_equal "/calendar/events/88/occurrences/2026-04-15.json", captured[:path]
    assert_includes captured[:pairs], [ "apply_to_future", "0" ]
    assert_includes captured[:pairs], [ "repeat_frequency", "custom" ]
  end

  test "delete_calendar_event uses JSON delete path" do
    client = HeyClient.new(@user)
    captured = nil
    client.define_singleton_method(:delete) do |path, allow: []|
      captured = { path: path }
      client.instance_variable_set(:@last_status_code, 204)
      {}
    end

    assert client.delete_calendar_event(calendar_id: "3", event_id: "8")
    assert_equal "/calendar/events/8.json", captured[:path]
  end

  test "delete_calendar_event occurrence sends apply_to_future=false" do
    client = HeyClient.new(@user)
    captured = nil
    client.define_singleton_method(:delete) do |path, allow: []|
      captured = { path: path }
      client.instance_variable_set(:@last_status_code, 204)
      {}
    end

    assert client.delete_calendar_event(calendar_id: "3", event_id: "88:2026-04-15")
    assert_equal "/calendar/events/88/occurrences/2026-04-15.json?apply_to_future=false", captured[:path]
  end

  test "start_time_track sends no body and adopts ongoing on 409" do
    client = HeyClient.new(@user)
    posts = []
    client.define_singleton_method(:request) do |method, path, body = nil, allow: []|
      if method == :post
        posts << { path: path, body: body, allow: allow }
        client.instance_variable_set(:@last_status_code, 409)
        return nil
      end
      { "id" => 321 }
    end

    result = client.start_time_track

    assert_equal 1, posts.size
    assert_equal "/calendar/ongoing_time_track.json", posts[0][:path]
    assert_nil posts[0][:body]
    assert_includes posts[0][:allow], 409
    assert_equal 321, result["id"]
  end

  test "stop_time_track wraps ends_at under calendar_time_track" do
    client = HeyClient.new(@user)
    captured = nil
    client.define_singleton_method(:request) do |method, path, body = nil, allow: []|
      captured = { method: method, path: path, body: body }
      {}
    end

    client.stop_time_track("44", category_title: "Focus work")

    assert_equal :put, captured[:method]
    assert_equal "/calendar/time_tracks/44.json", captured[:path]
    assert_equal "Focus work", captured[:body].dig("calendar_time_track", :category_title)
    assert captured[:body].dig("calendar_time_track", :ends_at).present?
  end

  test "email box methods use canonical laterbox asidebox trailbox paths" do
    client = HeyClient.new(@user)
    paths = []
    client.define_singleton_method(:get) do |path, allow: []|
      paths << path
      { "postings" => [] }
    end

    client.reply_later
    client.set_aside
    client.paper_trail

    assert_equal %w[/laterbox.json /asidebox.json /trailbox.json], paths
  end

  test "fetch_box follows Link rel=next when next_history_url is absent" do
    client = HeyClient.new(@user)
    paths = []
    client.define_singleton_method(:get) do |path, allow: []|
      paths << path
      if path == "/laterbox.json"
        client.instance_variable_set(:@last_link_header, '<https://app.hey.com/laterbox.json?page=abc>; rel="next"')
        { "postings" => [ { "id" => 1, "kind" => "topic" } ] }
      else
        client.instance_variable_set(:@last_link_header, nil)
        { "postings" => [ { "id" => 2, "kind" => "topic" } ] }
      end
    end

    rows = client.reply_later
    assert_equal 2, rows.size
    assert_includes paths, "/laterbox.json"
    assert_includes paths, "/laterbox.json?page=abc"
  end

  test "flatten_calendar_period expands occurrence_id into composite external id" do
    client = HeyClient.new(@user)
    raw = {
      "kind" => "week",
      "recordings" => {
        "Calendar::Event" => [
          {
            "id" => 0,
            "parent_id" => 88,
            "occurrence_id" => "_",
            "title" => "Weekly standup",
            "starts_at" => "2026-04-15T15:00:00Z",
            "ends_at" => "2026-04-15T15:30:00Z",
            "calendar" => { "id" => 7 }
          }
        ]
      }
    }

    rows = client.flatten_calendar_period(raw)
    assert_equal 1, rows.size
    assert_equal "88:2026-04-15", rows.first["id"]
    assert_equal "7", rows.first["hey_calendar_id"]
  end

  test "flatten_calendar_period prefers official occurrence_id over parent reconstruction" do
    client = HeyClient.new(@user)
    raw = {
      "kind" => "week",
      "recordings" => {
        "Calendar::Event" => [
          {
            "id" => 0,
            "parent_id" => 99,
            "occurrence_id" => "88_2026-04-15",
            "title" => "Weekly standup",
            "starts_at" => "2026-04-15T15:00:00Z",
            "ends_at" => "2026-04-15T15:30:00Z",
            "description" => "Agenda in notes",
            "location" => "Zoom",
            "url" => "https://meet.example.com/standup",
            "entry_id" => "77",
            "calendar" => { "id" => 7 }
          }
        ]
      }
    }

    rows = client.flatten_calendar_period(raw)
    assert_equal "88:2026-04-15", rows.first["id"]
    assert_equal "Agenda in notes", rows.first["description"]
    assert_equal "Zoom", rows.first["location"]
    assert_equal "https://meet.example.com/standup", rows.first["url"]
    assert_equal "77", rows.first["entry_id"]
  end

  test "flatten_calendar_period uses wall date from an offset evening timestamp" do
    @user.update!(timezone: "UTC")
    client = HeyClient.new(@user)
    raw = {
      "kind" => "week",
      "recordings" => {
        "Calendar::Event" => [
          {
            "id" => 0,
            "parent_id" => 88,
            "occurrence_id" => "_",
            "title" => "Evening class",
            "starts_at" => "2026-04-15T23:00:00-05:00",
            "ends_at" => "2026-04-15T23:45:00-05:00",
            "calendar" => { "id" => 7 }
          }
        ]
      }
    }

    rows = client.flatten_calendar_period(raw)
    assert_equal "88:2026-04-15", rows.first["id"]
  end

  test "calendar_week_events fetches /calendar/weeks/:date.json" do
    client = HeyClient.new(@user)
    paths = []
    client.define_singleton_method(:get) do |path, allow: []|
      paths << path
      { "kind" => "week", "recordings" => { "Calendar::Event" => [] } }
    end

    client.calendar_week_events("2026-04-13")
    assert_equal [ "/calendar/weeks/2026-04-13.json" ], paths
  end

  test "calendar_recordings follows Link rel=next" do
    client = HeyClient.new(@user)
    paths = []
    client.define_singleton_method(:get) do |path, allow: []|
      paths << path
      if path.start_with?("/calendars/42/recordings.json") && !path.include?("page=")
        client.instance_variable_set(:@last_link_header, '<https://app.hey.com/calendars/42/recordings.json?page=abc>; rel="next"')
        { "Calendar::Event" => [ { "id" => 1, "title" => "A", "starts_at" => "2026-04-10T14:00:00Z" } ] }
      else
        client.instance_variable_set(:@last_link_header, nil)
        { "Calendar::Event" => [ { "id" => 2, "title" => "B", "starts_at" => "2026-04-11T14:00:00Z" } ] }
      end
    end

    raw = client.calendar_recordings("42", starts_on: "2026-04-08", ends_on: "2026-04-14")
    assert_equal [ 1, 2 ], raw["Calendar::Event"].map { |r| r["id"] }
    assert(paths.any? { |p| p.start_with?("/calendars/42/recordings.json") && !p.include?("page=") })
    assert_includes paths, "/calendars/42/recordings.json?page=abc"
    assert client.instance_variable_get(:@last_recordings_complete)
  end

  test "calendar_events returns nil and recordings_complete is false when calendars.json fails" do
    client = HeyClient.new(@user)
    client.define_singleton_method(:get) { |_path| nil }

    assert_nil client.calendar_events(starts_on: "2026-04-08", ends_on: "2026-04-14")
    assert_equal false, client.recordings_complete?
  end

  test "todos returns nil and recordings_complete is false when calendars.json fails" do
    client = HeyClient.new(@user)
    client.define_singleton_method(:get) { |_path| nil }

    assert_nil client.todos
    assert_equal false, client.recordings_complete?
  end

  test "fetch_recordings_pages stops at the page cap and marks incomplete" do
    client = HeyClient.new(@user)
    client.define_singleton_method(:get) do |path, allow: []|
      client.instance_variable_set(:@last_link_header, '<https://app.hey.com/calendars/1/recordings.json?page=more>; rel="next"')
      { "Calendar::Event" => [ { "id" => path.object_id, "title" => "X", "starts_at" => "2026-04-10T14:00:00Z" } ] }
    end

    raw = client.send(:fetch_recordings_pages, "/calendars/1/recordings.json", max_pages: 2)
    assert_equal 2, raw["Calendar::Event"].size
    assert_equal false, client.instance_variable_get(:@last_recordings_complete)
  end
end
