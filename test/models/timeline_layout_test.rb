require "test_helper"

class TimelineLayoutTest < ActiveSupport::TestCase
  test "format_duration_hm" do
    assert_equal "45m", TimelineLayout.format_duration_hm(45)
    assert_equal "1h", TimelineLayout.format_duration_hm(60)
    assert_equal "1h 30m", TimelineLayout.format_duration_hm(90)
    assert_equal "2h 5m", TimelineLayout.format_duration_hm(125)
  end

  test "snap_duration_minutes" do
    assert_equal 15, TimelineLayout.snap_duration_minutes(8)
    assert_equal 45, TimelineLayout.snap_duration_minutes(52)
    assert_equal 60, TimelineLayout.snap_duration_minutes(58)
    assert_equal 90, TimelineLayout.snap_duration_minutes(88)
  end

  test "snap_zoned_time_to_grid" do
    tz = "America/Los_Angeles"
    t = Time.find_zone!(tz).local(2026, 4, 13, 14, 7, 0)
    snapped = TimelineLayout.snap_zoned_time_to_grid(t, tz)
    assert_equal 14, snapped.hour
    assert_includes [ 0, 15, 30, 45 ], snapped.min
  end
end
