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
end
