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

  # <html data-theme>: an explicit light/dark/paper choice; "system" leaves it off so the OS
  # decides, except on a Daylight tablet, where it means paper.
  def theme_attribute
    return ("paper" if daylight_device?) unless respond_to?(:logged_in?) && logged_in?
    # A Daylight is greyscale, so following the system or the sun means Paper there.
    return "paper" if current_user.theme.in?(%w[system sun]) && daylight_device?
    return current_user.sun_theme_now if current_user.theme == "sun"
    current_user.theme if current_user.theme.in?(%w[light dark paper])
  end

  # The Android app adds "Daylight" to its user agent on a Daylight DC-1.
  def daylight_device?
    request.user_agent.to_s.include?("Daylight")
  end

  def follows_the_sun?
    respond_to?(:logged_in?) && logged_in? && current_user.theme == "sun" && !daylight_device?
  end

  BASECAMP_RICH_TEXT_TAGS = %w[p br a ul ol li strong em b i del s div span h1 h2 h3 h4 blockquote code pre].freeze

  # Basecamp comments and descriptions are rich-text HTML: keep the formatting and
  # entities, drop anything that isn't plain markup.
  def basecamp_rich_text(html)
    clean = sanitize(flatten_bc_attachments(html.to_s), tags: BASECAMP_RICH_TEXT_TAGS, attributes: %w[href target rel class data-avatar])
    finish_rich_text(clean)
  end

  EMAIL_TAGS = (BASECAMP_RICH_TEXT_TAGS + %w[u h5 h6 hr table thead tbody tfoot tr td th caption small sub sup]).freeze

  # Email HTML is untrusted: keep its structure, drop scripts, styles, images
  # (tracking pixels) and every attribute except links.
  def email_html(html)
    doc = Nokogiri::HTML5.fragment(html.to_s)
    doc.css("style, script, head, title, img").each(&:remove)
    finish_rich_text(sanitize(doc.to_html, tags: EMAIL_TAGS, attributes: %w[href]))
  end

  # Basecamp embeds mentions and files as <bc-attachment>. Mentions become a
  # pill (photo filled in after sanitising, see finish_rich_text); files a chip.
  def flatten_bc_attachments(html)
    return html unless html.include?("bc-attachment")

    doc = Nokogiri::HTML5.fragment(html)
    doc.css("bc-attachment").each do |node|
      type = node["content-type"].to_s
      if type.include?("mention")
        name = node.at_css("figcaption")&.text.presence || node.text.strip
        pill = Nokogiri::XML::Node.new("span", doc.document)
        pill["class"] = "bc-mention"
        pill["data-avatar"] = node.at_css("img")&.[]("src").to_s
        pill.content = name.strip.split(/\s+/).first.to_s
        node.replace(pill)
      else
        label = node["filename"].presence || node.at_css("figcaption")&.text.presence || node["caption"].presence || "Attachment"
        chip = Nokogiri::XML::Node.new(node["href"].to_s.start_with?("https://") ? "a" : "span", doc.document)
        chip["class"] = "bc-file"
        chip["href"] = node["href"] if chip.name == "a"
        chip.content = "📎 #{label.strip}"
        node.replace(chip)
      end
    end
    doc.to_html
  end

  AUTOLINK = %r{\bhttps?://[^\s<>"']+[^\s<>"'.,;:!?)\]]}

  # Runs on already-sanitised HTML: links open in a new tab, bare URLs become
  # links, and mention pills get their photo through our avatar proxy.
  def finish_rich_text(html)
    doc = Nokogiri::HTML5.fragment(html.to_s)

    doc.xpath(".//text()[not(ancestor::a) and not(ancestor::pre) and not(ancestor::code)]").each do |text|
      next unless text.content.match?(AUTOLINK)

      fragment = text.content.split(/(#{AUTOLINK})/o).map do |part|
        part.match?(/\A#{AUTOLINK}\z/o) ? %(<a href="#{ERB::Util.h(part)}">#{ERB::Util.h(part)}</a>) : ERB::Util.h(part)
      end.join
      text.replace(Nokogiri::HTML5.fragment(fragment))
    end

    doc.css("a[href]").each do |a|
      a["target"] = "_blank"
      a["rel"] = "noopener noreferrer"
    end

    doc.css("span.bc-mention").each do |pill|
      src = pill.delete("data-avatar")&.value.to_s
      next unless src.match?(%r{\Ahttps://[^/]+/.*people/.+/avatar})

      img = Nokogiri::XML::Node.new("img", doc.document)
      img["src"] = basecamp_person_avatar_path(u: src)
      img["alt"] = ""
      img["class"] = "bc-mention__avatar"
      img["loading"] = "lazy"
      pill.prepend_child(img)
    end

    doc.to_html.html_safe
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
