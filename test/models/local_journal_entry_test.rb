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
end
