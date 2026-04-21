require "test_helper"

class CalendarEventTest < ActiveSupport::TestCase
  setup do
    @user = users(:one) # America/Los_Angeles
  end

  test "for_date picks up a timed event on the DST fall-back day (25-hour day)" do
    # US DST ends Sunday Nov 1 2026 at 2am local. Local time "wraps" 1:00-2:00 twice.
    # An event at 01:30 local on that day stored as UTC must still show on Nov 1.
    # Before DST (PDT = UTC-7), 01:30 local == 08:30 UTC.
    event = @user.calendar_events.create!(
      external_id: "dst-pdt-early",
      source: :hey,
      title: "Early meeting",
      starts_at: Time.utc(2026, 11, 1, 8, 30),
      ends_at: Time.utc(2026, 11, 1, 9, 30),
      all_day: false
    )

    assert_includes @user.calendar_events.for_date(Date.new(2026, 11, 1), @user.timezone).to_a, event
  end

  test "for_date picks up an event at 01:30 local after DST fall-back (second wall-clock pass)" do
    # After DST (PST = UTC-8), 01:30 local == 09:30 UTC.
    event = @user.calendar_events.create!(
      external_id: "dst-pst-late",
      source: :hey,
      title: "Second 1:30",
      starts_at: Time.utc(2026, 11, 1, 9, 30),
      ends_at: Time.utc(2026, 11, 1, 10, 30),
      all_day: false
    )

    assert_includes @user.calendar_events.for_date(Date.new(2026, 11, 1), @user.timezone).to_a, event
  end

  test "for_date includes an all-day event stored at UTC midnight" do
    event = @user.calendar_events.create!(
      external_id: "all-day-dst",
      source: :hey,
      title: "Holiday",
      starts_at: Time.utc(2026, 11, 1, 0, 0),
      all_day: true
    )

    assert_includes @user.calendar_events.for_date(Date.new(2026, 11, 1), @user.timezone).to_a, event
  end
end
