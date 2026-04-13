require "test_helper"

class LocalJournalEntryTest < ActiveSupport::TestCase
  test "plain_text_from_editor leaves plain strings unchanged" do
    assert_equal "Evening reflection", LocalJournalEntry.plain_text_from_editor("Evening reflection")
  end

  test "plain_text_from_editor strips HTML and preserves line breaks" do
    html = "<p>Line one</p><br><p>Line two</p>"
    out = LocalJournalEntry.plain_text_from_editor(html)
    assert_includes out, "Line one"
    assert_includes out, "Line two"
  end

  test "content_from_hey_api passes HTML through unchanged" do
    html = "<div class=\"trix-content\"><p>Hi <strong>there</strong></p></div>"
    assert_equal html, LocalJournalEntry.content_from_hey_api(html)
  end

  test "content_from_hey_api wraps plain payloads as scratchpad HTML" do
    out = LocalJournalEntry.content_from_hey_api("Hello\n\nSecond")
    assert_includes out, "Hello"
    assert_includes out, "Second"
    assert_includes out, "<p>"
  end
end
