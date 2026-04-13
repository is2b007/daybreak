require "test_helper"

class CalendarEventTimelineTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
  end

  test "to_timeline_hash all_day has small strip at top" do
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
    assert h[:top_px] < 10
    assert h[:height_px].positive?
    assert h.key?(:id)
    assert h.key?(:starts_at_iso)
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
