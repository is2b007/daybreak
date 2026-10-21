class LocalJournalEntry < ApplicationRecord
  belongs_to :user

  validates :date, presence: true, uniqueness: { scope: :user_id }
  validates :content, presence: true

  def content_digest
    Digest::SHA256.hexdigest(content.to_s)
  end

  # HEY Journal uses Trix; the API `content` field is HTML. The scratchpad stores HTML
  # from contenteditable; we send that through on sync (see SyncJournalJob).
  def plain_text_for_hey
    self.class.plain_text_from_editor(content)
  end

  # The "Day log" block SyncJournalJob appends after the scratchpad. HEY hands it
  # back on the next read; it is rebuilt from the day's log on every push.
  DAY_LOG_APPENDIX_HTML = %r{\s*<(p|div)\b[^>]*>\s*---\s*<br\s*/?>\s*Day log\b.*\z}mi
  DAY_LOG_APPENDIX_TEXT = /\s*^---\s*\n\s*Day log\b.*\z/m

  # Normalize HEY `journal_entry` JSON `content` into the HTML we persist locally:
  # without the Action Text layout HEY wraps reads in, and without our own day log,
  # so neither nests or repeats on the next push.
  def self.content_from_hey_api(raw)
    s = unwrap_trix_layout(raw.to_s.strip)
    return "" if s.blank?
    return s.sub(DAY_LOG_APPENDIX_HTML, "").strip if s.include?("<")

    html_from_plain_text(s.sub(DAY_LOG_APPENDIX_TEXT, ""))
  end

  # HEY serves rich text through Action Text's <div class="trix-content"> layout; a
  # write that keeps it is stored inside it, and the next read adds another.
  def self.unwrap_trix_layout(html)
    loop do
      return html unless html.include?("trix-content")

      nodes = Nokogiri::HTML::DocumentFragment.parse(html).children.reject { |n| n.text? && n.text.strip.empty? }
      wrapper = nodes.first
      return html unless nodes.one? && wrapper.element? && wrapper.name == "div" &&
        wrapper["class"].to_s.split.include?("trix-content")

      html = wrapper.inner_html.strip
    end
  end

  def self.plain_text_from_editor(raw)
    str = raw.to_s.strip
    return "" if str.blank?
    return str unless str.include?("<")

    normalized = str.gsub(/\r\n?/, "\n")
      .gsub(/<br\s*\/?>/i, "\n")
      .gsub(/<\/(p|div|h[1-6]|blockquote|pre|tr)>/i, "\n")
      .gsub(/<\/(ul|ol)>/i, "\n")
      .gsub(/<li>/i, "\n• ")
      .gsub(/<\/li>/i, "")

    plain = ActionController::Base.helpers.strip_tags(normalized)
    plain.gsub(/[ \t\f\v]+\n/, "\n")
      .gsub(/\n[ \t\f\v]+/, "\n")
      .gsub(/\n{3,}/, "\n\n")
      .strip
  end

  # When HEY returns plain text (no tags), wrap as simple HTML for the scratchpad editor.
  def self.html_from_plain_text(plain)
    str = plain.to_s.strip
    return "" if str.blank?

    escaped = ERB::Util.html_escape(str)
    parts = escaped.split(/\n{2,}/)
    parts.map { |p| "<p>#{p.gsub("\n", '<br>')}</p>" }.join
  end
end
