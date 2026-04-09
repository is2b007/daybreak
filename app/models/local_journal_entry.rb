class LocalJournalEntry < ApplicationRecord
  belongs_to :user

  validates :date, presence: true, uniqueness: { scope: :user_id }
  validates :content, presence: true

  # HEY journal API expects plain text. Rich-text HTML from the scratchpad editor
  # and plain text from rituals both pass through here before sync.
  def plain_text_for_hey
    self.class.plain_text_from_editor(content)
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
end
