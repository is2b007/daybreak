module ApplicationHelper
  # Solid 24px glyph from app/assets/images/icons (Fizzy's set), painted as a CSS
  # mask so it takes the surrounding text colour. Decorative unless a label is given.
  def icon(name, label: nil, class: nil)
    tag.span class: [ "icon", binding.local_variable_get(:class) ],
      style: "--svg: url('#{asset_path("icons/#{name}.svg")}')",
      role: (label ? "img" : nil), "aria-label": label, "aria-hidden": (label ? nil : "true")
  end

  # Full-colour app tile for an integration (Basecamp, HEY), as on the rail and task cards.
  def source_tile(name, class: nil)
    image_tag "tiles/#{name}.png", alt: "", class: [ "src-tile", binding.local_variable_get(:class) ], decoding: "async"
  end

  # <html data-theme>: an explicit light/dark choice; "system" leaves it off so the OS decides.
  def theme_attribute
    current_user.theme if respond_to?(:logged_in?) && logged_in? && current_user.theme.in?(%w[light dark])
  end

  BASECAMP_RICH_TEXT_TAGS = %w[p br a ul ol li strong em b i del s div span h1 h2 h3 h4 blockquote code pre].freeze

  # Basecamp comments and descriptions are rich-text HTML: keep the formatting and
  # entities, drop anything that isn't plain markup.
  def basecamp_rich_text(html)
    sanitize(flatten_bc_attachments(html.to_s), tags: BASECAMP_RICH_TEXT_TAGS, attributes: %w[href target rel class])
  end

  EMAIL_TAGS = (BASECAMP_RICH_TEXT_TAGS + %w[u h5 h6 hr table thead tbody tfoot tr td th caption small sub sup]).freeze

  # Email HTML is untrusted: keep its structure, drop scripts, styles, images
  # (tracking pixels) and every attribute except links.
  def email_html(html)
    doc = Nokogiri::HTML5.fragment(html.to_s)
    doc.css("style, script, head, title, img").each(&:remove)
    doc.css("a[href]").each do |a|
      a["target"] = "_blank"
      a["rel"] = "noopener noreferrer"
    end
    sanitize(doc.to_html, tags: EMAIL_TAGS, attributes: %w[href target rel])
  end

  # Basecamp embeds mentions and files as <bc-attachment>. Sanitising alone keeps
  # only stray caption text, so turn them into "@Name" and a file chip first.
  def flatten_bc_attachments(html)
    return html unless html.include?("bc-attachment")

    doc = Nokogiri::HTML5.fragment(html)
    doc.css("bc-attachment").each do |node|
      type = node["content-type"].to_s
      if type.include?("mention")
        name = node.at_css("figcaption")&.text.presence || node.text.strip
        node.replace(Nokogiri::XML::Text.new("@#{name.strip}", doc.document))
      else
        label = node["filename"].presence || node.at_css("figcaption")&.text.presence || node["caption"].presence || "Attachment"
        chip = Nokogiri::XML::Node.new("span", doc.document)
        chip["class"] = "bc-file"
        chip.content = "📎 #{label.strip}"
        node.replace(chip)
      end
    end
    doc.to_html
  end

  def format_sunset_hm(minutes)
    m = minutes.to_i
    return "0:00" if m <= 0

    h, r = m.divmod(60)
    "#{h}:#{r.to_s.rjust(2, '0')}"
  end

  def format_sunset_hours_badge(minutes)
    m = minutes.to_f
    return "0 hr" if m <= 0

    h = m / 60.0
    if (h % 1).abs < 0.05
      "#{h.round} hr"
    else
      "#{format('%.1f', h).sub(/\.0$/, '')} hr"
    end
  end

  def sunset_donut_gradient(segments)
    return nil if segments.blank?

    total = segments.sum { |s| s[:minutes] }.to_f
    return nil if total <= 0

    parts = []
    cumulative = 0.0
    segments.each do |s|
      start_pct = (cumulative / total * 100).round(4)
      cumulative += s[:minutes]
      end_pct = (cumulative / total * 100).round(4)
      parts << "#{s[:color]} #{start_pct}% #{end_pct}%"
    end
    "conic-gradient(#{parts.join(', ')})"
  end

  def format_sunrise_minutes(minutes)
    m = minutes.to_i
    return "0 min" if m <= 0

    h, r = m.divmod(60)
    if h.positive?
      r.positive? ? "#{h}h #{r}m" : "#{h}h"
    else
      "#{r} min"
    end
  end

  def format_focus_duration(minutes)
    m = minutes.to_i
    h, r = m.divmod(60)
    "#{h}:#{r.to_s.rjust(2, '0')}:00"
  end

  # Tag the focus overlay with a time-of-day phase so its ambient backdrop can
  # shift (dawn → morning → midday → golden → dusk → night). Uses the viewer's
  # timezone so a user in Lisbon sees dusk at 7pm Lisbon, not 7pm UTC.
  def focus_time_phase(user = current_user)
    tz = (user && user.timezone.presence) || Time.zone.name
    hour = Time.current.in_time_zone(tz).hour
    case hour
    when 5..7   then "dawn"
    when 8..11  then "morning"
    when 12..14 then "midday"
    when 15..17 then "golden"
    when 18..20 then "dusk"
    else             "night"
    end
  end
  CONTACT_HUES = [ 25, 60, 145, 190, 230, 265, 300, 340 ].freeze

  # Initials circle for an email sender: same name, same colour, every time.
  def contact_avatar(name, email = nil)
    label = name.presence || email.to_s.split("@").first.to_s
    words = label.scan(/[[:alnum:]]+/)
    initials = (words.size > 1 ? words.first(2).map { |w| w[0] } : [ words.first.to_s[0, 2] ]).join.upcase.presence || "?"
    hue = CONTACT_HUES[Zlib.crc32((email.presence || label).downcase) % CONTACT_HUES.size]
    tag.span(initials, class: "contact-avatar", style: "--contact-hue: #{hue}", aria: { hidden: true })
  end

  # "2:00am" for today, "Oct 21" for this year, "Oct 21, 2025" before that — as an inbox shows it.
  def inbox_time(time)
    return "" if time.blank?

    local = time.in_time_zone
    if local.to_date == Time.zone.today
      local.strftime("%-l:%M%P")
    elsif local.year == Time.zone.today.year
      local.strftime("%b %-d")
    else
      local.strftime("%b %-d, %Y")
    end
  end
end
