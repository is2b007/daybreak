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

  test "basecamp_rich_text turns mentions into photo pills and files into chips" do
    avatar = "https://3.basecamp.com/1/people/abc/avatar"
    html = basecamp_rich_text(<<~HTML)
      <div>Ask <bc-attachment content-type="application/vnd.basecamp.mention"><figure><img src="#{avatar}"><figcaption>Jason Fried</figcaption></figure></bc-attachment>
      about <bc-attachment content-type="image/png" filename="hero.png"><figure><img src="b.png"></figure></bc-attachment></div>
    HTML

    assert_includes html, %(<span class="bc-mention"><img src="#{basecamp_person_avatar_path(u: avatar)}" alt="" class="bc-mention__avatar" loading="lazy">Jason</span>)
    assert_includes html, %(<span class="bc-file">📎 hero.png</span>)
    refute_includes html, "b.png"
  end

  test "mention photos only come from Basecamp avatar URLs" do
    html = basecamp_rich_text(%(<bc-attachment content-type="application/vnd.basecamp.mention"><figure><img src="https://evil.example/x.png"><figcaption>Eve</figcaption></figure></bc-attachment>))

    assert_includes html, %(<span class="bc-mention">Eve</span>)
    refute_includes html, "evil.example"
  end

  test "bare URLs become links, but not inside code or existing links" do
    html = basecamp_rich_text(%(<div>See https://example.com/a?b=1. <a href="https://x.example">https://x.example</a> <code>https://code.example</code></div>))

    assert_includes html, %(<a href="https://example.com/a?b=1" target="_blank" rel="noopener noreferrer">https://example.com/a?b=1</a>.)
    assert_equal 1, html.scan("https://x.example</a>").size
    assert_includes html, "<code>https://code.example</code>"
  end
end
