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
      starts_at: Time.zone.parse("2026-04-14 12:00"),
      ends_at: Time.zone.parse("2026-04-14 13:00"),
      all_day: false,
      hey_calendar_id: "1"
    )
    @user.calendar_events.create!(
      source: :hey,
      external_id: "x2",
      title: "Dup",
      starts_at: Time.zone.parse("2026-04-14 12:00"),
      ends_at: Time.zone.parse("2026-04-14 13:00"),
      all_day: false,
      hey_calendar_id: "1"
    )

    client = Object.new
    client.define_singleton_method(:calendar_events) { |**_| [] }

    with_hey_client(client) do
      SyncCalendarEventsJob.perform_now(@user.id, week_start: @week.iso8601)
    end

    assert_equal 1, @user.calendar_events.where(source: :hey, title: "Dup").count
  end

  test "dedupes hey recordings that share title and time range but differ by calendar or id" do
    client = Object.new
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
end
