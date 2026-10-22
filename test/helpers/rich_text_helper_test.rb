require "test_helper"

class RichTextHelperTest < ActionView::TestCase
  include ApplicationHelper

  test "email_html keeps structure and links, drops scripts, styles, images and attributes" do
    html = email_html(<<~HTML)
      <style>p { color: red }</style>
      <p style="color:blue">Hi <b>Kosta</b><img src="https://t.example/p.gif"> <a href="https://e.example" onclick="x()">link</a></p>
      <script>alert(1)</script>
      <table><tr><td>cell</td></tr></table>
    HTML

    assert_includes html, "<b>Kosta</b>"
    assert_includes html, %(<a href="https://e.example" target="_blank" rel="noopener noreferrer">link</a>)
    assert_includes html, "<td>cell</td>"
    refute_match(/style|script|img|onclick|color: red|alert/, html)
  end

  test "basecamp_rich_text turns mentions and files into readable text" do
    html = basecamp_rich_text(<<~HTML)
      <div>Ask <bc-attachment content-type="application/vnd.basecamp.mention"><figure><img src="a.png"><figcaption>Jason Fried</figcaption></figure></bc-attachment>
      about <bc-attachment content-type="image/png" filename="hero.png"><figure><img src="b.png"></figure></bc-attachment></div>
    HTML

    assert_includes html, "@Jason Fried"
    assert_includes html, %(<span class="bc-file">📎 hero.png</span>)
    refute_includes html, "<img"
  end
end
