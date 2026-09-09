require "test_helper"

class SyncCalendarEventsJobTest < ActiveJob::TestCase
  setup do
    @user = users(:one)
    @user.update!(
      hey_access_token: "stub",
      hey_refresh_token: "stub-r",
      hey_token_expires_at: 2.weeks.from_now,
      basecamp_access_token: nil
    )
    @week = Date.new(2026, 4, 13).beginning_of_week(:monday)
  end

  def with_hey_client(client)
    original = HeyClient.method(:new)
    HeyClient.define_singleton_method(:new) { |_u| client }
    yield
  ensure
    HeyClient.define_singleton_method(:new, original)
  end

  test "sync_hey uses provided week_start for calendar_events window" do
    seen = []
    client = Object.new
    client.define_singleton_method(:calendar_week_events) { |*| [] }
    client.define_singleton_method(:calendar_events) do |starts_on:, ends_on:|
      seen << [ starts_on, ends_on ]
      []
    end

    with_hey_client(client) do
      SyncCalendarEventsJob.perform_now(@user.id, week_start: @week.iso8601)
    end

    assert_equal 1, seen.size
    assert_equal @week.iso8601, seen[0][0]
    assert_equal (@week + 6.days).iso8601, seen[0][1]
  end

  test "upserts hey event with camelCase keys" do
    client = Object.new
    client.define_singleton_method(:calendar_week_events) { |*| [] }
    client.define_singleton_method(:calendar_events) do |starts_on:, ends_on:|
      [
        {
          "id" => "cal-1",
          "hey_calendar_id" => "owner-7",
          "title" => "Standup",
          "startsAt" => "2026-04-15T15:00:00Z",
          "endsAt" => "2026-04-15T15:30:00Z",
          "allDay" => false
        }
      ]
    end

    with_hey_client(client) do
      SyncCalendarEventsJob.perform_now(@user.id, week_start: @week.iso8601)
    end

    ev = @user.calendar_events.find_by(external_id: "cal-1", source: :hey)
    assert ev
    assert_equal "Standup", ev.title
    assert_equal "owner-7", ev.hey_calendar_id
  end

  test "reconcile removes duplicate hey rows already stored under different external_ids" do
    @user.calendar_events.create!(
      source: :hey,
      external_id: "x1",
      title: "Dup",
      starts_at: Time.zone.parse("2026-03-01 12:00"),
      ends_at: Time.zone.parse("2026-03-01 13:00"),
      all_day: false,
      hey_calendar_id: "1"
    )
    @user.calendar_events.create!(
      source: :hey,
      external_id: "x2",
      title: "Dup",
      starts_at: Time.zone.parse("2026-03-01 12:00"),
      ends_at: Time.zone.parse("2026-03-01 13:00"),
      all_day: false,
      hey_calendar_id: "1"
    )

    client = Object.new
    client.define_singleton_method(:calendar_week_events) { |*| [] }
    client.define_singleton_method(:calendar_events) { |**_| [] }

    with_hey_client(client) do
      SyncCalendarEventsJob.perform_now(@user.id, week_start: @week.iso8601)
    end

    assert_equal 1, @user.calendar_events.where(source: :hey, title: "Dup").count
  end

  test "dedupes hey recordings that share title and time range but differ by calendar or id" do
    client = Object.new
    client.define_singleton_method(:calendar_week_events) { |*| [] }
    client.define_singleton_method(:calendar_events) do |starts_on:, ends_on:|
      [
        {
          "id" => "dup-a",
          "hey_calendar_id" => "9",
          "title" => "Same slot",
          "starts_at" => "2026-04-14T17:00:00Z",
          "ends_at" => "2026-04-14T18:00:00Z",
          "all_day" => false
        },
        {
          "id" => "dup-b",
          "hey_calendar_id" => "8",
          "title" => "Same slot",
          "starts_at" => "2026-04-14T17:00:00Z",
          "ends_at" => "2026-04-14T18:00:00Z",
          "all_day" => false
        }
      ]
    end

    with_hey_client(client) do
      SyncCalendarEventsJob.perform_now(@user.id, week_start: @week.iso8601)
    end

    assert_equal 1, @user.calendar_events.where(source: :hey, title: "Same slot").count
    # Lower hey_calendar_id wins ties so the row from calendar "8" is kept.
    assert @user.calendar_events.exists?(external_id: "dup-b", source: :hey)
    assert_not @user.calendar_events.exists?(external_id: "dup-a", source: :hey)
  end

  test "upserts hey events with completed_at from flattened recordings" do
    client = Object.new
    client.define_singleton_method(:calendar_week_events) { |*| [] }
    client.define_singleton_method(:calendar_events) do |starts_on:, ends_on:|
      [
        {
          "id" => "9001",
          "hey_calendar_id" => "owner-99",
          "title" => "From recordings",
          "starts_at" => "2026-04-14T17:00:00Z",
          "ends_at" => "2026-04-14T18:00:00Z",
          "all_day" => false,
          "completed_at" => "2026-04-14T16:00:00Z"
        }
      ]
    end

    with_hey_client(client) do
      SyncCalendarEventsJob.perform_now(@user.id, week_start: @week.iso8601)
    end

    ev = @user.calendar_events.find_by(external_id: "9001", source: :hey)
    assert ev
    assert_equal "From recordings", ev.title
    assert_equal "owner-99", ev.hey_calendar_id
    assert ev.completed_at.present?
  end

  test "upserts expanded recurring occurrence from calendar_week_events" do
    week = @week
    client = Object.new
    client.define_singleton_method(:calendar_week_events) do |date|
      raise "unexpected week #{date}" unless date == week.iso8601
      [
        {
          "id" => "88:2026-04-15",
          "hey_calendar_id" => "cal-1",
          "title" => "Weekly standup",
          "starts_at" => "2026-04-15T15:00:00Z",
          "ends_at" => "2026-04-15T15:30:00Z",
          "all_day" => false,
          "occurrence_id" => "_"
        }
      ]
    end
    client.define_singleton_method(:calendar_events) { |**_| [] }

    with_hey_client(client) do
      SyncCalendarEventsJob.perform_now(@user.id, week_start: @week.iso8601)
    end

    ev = @user.calendar_events.find_by(external_id: "88:2026-04-15", source: :hey)
    assert ev
    assert_equal "Weekly standup", ev.title
  end

  test "upserts hey event notes location meeting url and attached entry" do
    client = Object.new
    client.define_singleton_method(:calendar_week_events) { |*| [] }
    client.define_singleton_method(:calendar_events) do |starts_on:, ends_on:|
      [
        {
          "id" => "cal-notes",
          "hey_calendar_id" => "owner-7",
          "title" => "Standup",
          "starts_at" => "2026-04-15T15:00:00Z",
          "ends_at" => "2026-04-15T15:30:00Z",
          "all_day" => false,
          "description" => "Bring slides",
          "location" => "Room 4",
          "url" => "https://meet.example.com/x",
          "entry_id" => "55"
        }
      ]
    end

    with_hey_client(client) do
      SyncCalendarEventsJob.perform_now(@user.id, week_start: @week.iso8601)
    end

    ev = @user.calendar_events.find_by(external_id: "cal-notes", source: :hey)
    assert ev
    assert_equal "Bring slides", ev.description
    assert_equal "Room 4", ev.location
    assert_equal "https://meet.example.com/x", ev.hey_event_url
    assert_equal "55", ev.hey_entry_id
  end

  test "prunes in-window hey events missing from a complete fetch" do
    gone = @user.calendar_events.create!(
      source: :hey,
      external_id: "gone",
      title: "Deleted in HEY",
      starts_at: Time.zone.parse("2026-04-14 12:00"),
      ends_at: Time.zone.parse("2026-04-14 13:00"),
      all_day: false
    )
    later = @user.calendar_events.create!(
      source: :hey,
      external_id: "later",
      title: "Next month",
      starts_at: Time.zone.parse("2026-05-20 12:00"),
      ends_at: Time.zone.parse("2026-05-20 13:00"),
      all_day: false
    )
    local = @user.calendar_events.create!(
      source: :daybreak,
      external_id: "daybreak-tbox-1",
      title: "Local timebox",
      starts_at: Time.zone.parse("2026-04-14 09:00"),
      ends_at: Time.zone.parse("2026-04-14 10:00"),
      all_day: false
    )

    client = Object.new
    client.define_singleton_method(:calendar_week_events) { |*| [] }
    client.define_singleton_method(:calendar_events) do |starts_on:, ends_on:|
      [
        {
          "id" => "kept",
          "hey_calendar_id" => "1",
          "title" => "Still there",
          "starts_at" => "2026-04-14T17:00:00Z",
          "ends_at" => "2026-04-14T18:00:00Z",
          "all_day" => false
        }
      ]
    end
    client.define_singleton_method(:recordings_complete?) { true }

    with_hey_client(client) do
      SyncCalendarEventsJob.perform_now(@user.id, week_start: @week.iso8601)
    end

    assert_not CalendarEvent.exists?(gone.id)
    assert CalendarEvent.exists?(later.id)
    assert CalendarEvent.exists?(local.id)
    assert @user.calendar_events.exists?(external_id: "kept", source: :hey)
  end

  test "does not prune when recordings fetch is incomplete" do
    stale = @user.calendar_events.create!(
      source: :hey,
      external_id: "stale",
      title: "Keep me",
      starts_at: Time.zone.parse("2026-04-14 12:00"),
      ends_at: Time.zone.parse("2026-04-14 13:00"),
      all_day: false
    )

    client = Object.new
    client.define_singleton_method(:calendar_week_events) { |*| [] }
    client.define_singleton_method(:calendar_events) { |**_| [] }
    client.define_singleton_method(:recordings_complete?) { false }

    with_hey_client(client) do
      SyncCalendarEventsJob.perform_now(@user.id, week_start: @week.iso8601)
    end

    assert CalendarEvent.exists?(stale.id)
  end

  test "does not prune when hey fetch returns nil" do
    stale = @user.calendar_events.create!(
      source: :hey,
      external_id: "stale-nil",
      title: "Keep me",
      starts_at: Time.zone.parse("2026-04-14 12:00"),
      ends_at: Time.zone.parse("2026-04-14 13:00"),
      all_day: false
    )

    client = Object.new
    client.define_singleton_method(:calendar_week_events) { |*| nil }
    client.define_singleton_method(:calendar_events) { |**_| nil }

    with_hey_client(client) do
      SyncCalendarEventsJob.perform_now(@user.id, week_start: @week.iso8601)
    end

    assert CalendarEvent.exists?(stale.id)
  end

  test "empty complete fetch prunes in-window hey events" do
    stale = @user.calendar_events.create!(
      source: :hey,
      external_id: "empty-gone",
      title: "Gone",
      starts_at: Time.zone.parse("2026-04-14 12:00"),
      ends_at: Time.zone.parse("2026-04-14 13:00"),
      all_day: false
    )

    client = Object.new
    client.define_singleton_method(:calendar_week_events) { |*| [] }
    client.define_singleton_method(:calendar_events) { |**_| [] }
    client.define_singleton_method(:recordings_complete?) { true }

    with_hey_client(client) do
      SyncCalendarEventsJob.perform_now(@user.id, week_start: @week.iso8601)
    end

    assert_not CalendarEvent.exists?(stale.id)
  end
end
