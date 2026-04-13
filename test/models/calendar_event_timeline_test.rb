require "test_helper"

class CalendarEventTimelineTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
  end

  test "to_timeline_hash all_day has strip metadata without fractional hours" do
    e = CalendarEvent.new(
      user: @user,
      external_id: "a1",
      source: :hey,
      title: "Holiday",
      starts_at: Time.zone.parse("2026-04-13 00:00"),
      ends_at: Time.zone.parse("2026-04-13 23:59"),
      all_day: true
    )
    h = e.to_timeline_hash("America/Los_Angeles")
    assert h[:all_day]
    refute h.key?(:top_offset_hours)
    assert h.key?(:id)
    assert h.key?(:starts_at_iso)
  end

  test "to_timeline_hash returns fractional hours for timed events" do
    la = Time.find_zone("America/Los_Angeles")
    e = CalendarEvent.new(
      user: @user,
      external_id: "a3",
      source: :hey,
      title: "Lunch",
      starts_at: la.parse("2026-04-13 12:30"),
      ends_at: la.parse("2026-04-13 13:30"),
      all_day: false
    )
    h = e.to_timeline_hash("America/Los_Angeles")
    assert h[:top_offset_hours].positive?
    assert h[:height_hours].positive?
  end

  test "to_timeline_hash marks completed HEY events" do
    la = Time.find_zone("America/Los_Angeles")
    e = CalendarEvent.new(
      user: @user,
      external_id: "a4",
      source: :hey,
      title: "Done",
      starts_at: la.parse("2026-04-13 12:00"),
      ends_at: la.parse("2026-04-13 13:00"),
      all_day: false,
      completed_at: la.parse("2026-04-13 11:00")
    )
    h = e.to_timeline_hash("America/Los_Angeles")
    assert h[:completed]
  end

  test "to_timeline_hash returns nil for events entirely before timeline" do
    e = CalendarEvent.new(
      user: @user,
      external_id: "a2",
      source: :hey,
      title: "Early",
      starts_at: Time.zone.parse("2026-04-13 05:00"),
      ends_at: Time.zone.parse("2026-04-13 06:00"),
      all_day: false
    )
    assert_nil e.to_timeline_hash("America/Los_Angeles")
  end

  test "day_view_chip_records drops HEY all-day chip when timed block shares title" do
    la = Time.find_zone("America/Los_Angeles")
    day = Date.parse("2026-04-13")
    @user.calendar_events.create!(
      external_id: "allday-dup",
      source: :hey,
      title: "Address Gaps",
      starts_at: la.parse("2026-04-13 00:00"),
      ends_at: la.parse("2026-04-19 00:00"),
      all_day: true,
      hey_calendar_id: "1"
    )
    @user.calendar_events.create!(
      external_id: "timed-dup",
      source: :hey,
      title: "Address Gaps",
      starts_at: la.parse("2026-04-13 09:00"),
      ends_at: la.parse("2026-04-13 10:00"),
      all_day: false,
      hey_calendar_id: "1"
    )
    chips = CalendarEvent.day_view_chip_records(@user, day)
    assert_equal 1, chips.size
    assert_equal "timed-dup", chips.first.external_id
  end

  test "for_day_chip_strip excludes daybreak timeline mirrors" do
    la = Time.find_zone("America/Los_Angeles")
    day = Date.parse("2026-04-13")
    @user.calendar_events.create!(
      external_id: "chip-hey",
      source: :hey,
      title: "Hey timed",
      starts_at: la.parse("2026-04-13 09:00"),
      ends_at: la.parse("2026-04-13 10:00"),
      all_day: false
    )
    @user.calendar_events.create!(
      external_id: CalendarEvent.daybreak_timebox_external_id(999),
      source: :daybreak,
      title: "Mirror",
      starts_at: la.parse("2026-04-13 08:30"),
      ends_at: la.parse("2026-04-13 10:30"),
      all_day: false
    )
    rows = @user.calendar_events.for_date(day).for_day_chip_strip
    assert_equal 1, rows.size
    assert_equal "chip-hey", rows.first.external_id
  end

  test "hourly timeline payload drops all-day entries" do
    la = Time.find_zone("America/Los_Angeles")
    all_day = CalendarEvent.new(
      user: @user,
      external_id: "ad1",
      source: :hey,
      title: "Holiday",
      starts_at: la.parse("2026-04-13 00:00"),
      ends_at: la.parse("2026-04-13 23:59"),
      all_day: true
    )
    timed = CalendarEvent.new(
      user: @user,
      external_id: "td1",
      source: :hey,
      title: "Meet",
      starts_at: la.parse("2026-04-13 12:00"),
      ends_at: la.parse("2026-04-13 13:00"),
      all_day: false
    )
    tz = "America/Los_Angeles"
    rows = [ all_day, timed ].map { |e| e.to_timeline_hash(tz) }.compact.reject { |h| h[:all_day] }
    assert_equal 1, rows.size
    assert_equal "Meet", rows.first[:title]
  end
end
