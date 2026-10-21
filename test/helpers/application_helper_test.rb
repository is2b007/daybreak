require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "basecamp_rich_text keeps formatting and entities without escaping them twice" do
    html = basecamp_rich_text("<div>Fish &amp; chips<br><strong>today</strong></div>")

    assert_equal "<div>Fish &amp; chips<br><strong>today</strong></div>", html
  end

  test "basecamp_rich_text drops scripts, handlers and javascript links" do
    html = basecamp_rich_text(%(<div onclick="x()">Hi<script>alert(1)</script><a href="javascript:alert(1)">link</a></div>))

    refute_includes html, "script"
    refute_includes html, "onclick"
    refute_includes html, "javascript:"
    assert_includes html, "link"
  end
end
