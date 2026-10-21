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
    html = "<p>Hi <strong>there</strong></p>"
    assert_equal html, LocalJournalEntry.content_from_hey_api(html)
  end

  test "content_from_hey_api drops HEY's trix-content layout, however deep it has nested" do
    html = "<div class=\"trix-content\">\n  <div class=\"trix-content\"><p>Hi <strong>there</strong></p></div>\n</div>"
    assert_equal "<p>Hi <strong>there</strong></p>", LocalJournalEntry.content_from_hey_api(html)
  end

  test "content_from_hey_api keeps a trix-content div that is not the outer wrapper" do
    html = "<p>Before</p><div class=\"trix-content\">Quoted</div>"
    assert_equal html, LocalJournalEntry.content_from_hey_api(html)
  end

  test "content_from_hey_api drops the day log Daybreak appended" do
    html = "<div class=\"trix-content\"><p>Scratch</p>\n\n<div>---<br>Day log<br><br>9:00am<br>Logged item</div></div>"
    assert_equal "<p>Scratch</p>", LocalJournalEntry.content_from_hey_api(html)
  end

  test "content_from_hey_api wraps plain payloads as scratchpad HTML" do
    out = LocalJournalEntry.content_from_hey_api("Hello\n\nSecond")
    assert_includes out, "Hello"
    assert_includes out, "Second"
    assert_includes out, "<p>"
  end
end
