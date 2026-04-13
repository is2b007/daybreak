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

  # Normalize HEY `journal_entry` JSON `content` into the HTML we persist locally.
  def self.content_from_hey_api(raw)
    s = raw.to_s.strip
    return "" if s.blank?
    return s if s.include?("<")

    html_from_plain_text(s)
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
