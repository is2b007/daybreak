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
    image_tag "tiles/#{name}.svg", alt: "", class: [ "src-tile", binding.local_variable_get(:class) ], decoding: "async"
  end

  # <html data-theme>: an explicit light/dark choice; "system" leaves it off so the OS decides.
  def theme_attribute
    current_user.theme if respond_to?(:logged_in?) && logged_in? && current_user.theme.in?(%w[light dark])
  end

  BASECAMP_RICH_TEXT_TAGS = %w[p br a ul ol li strong em b i del s div span h1 h2 h3 h4 blockquote code pre].freeze

  # Basecamp comments and descriptions are rich-text HTML: keep the formatting and
  # entities, drop anything that isn't plain markup.
  def basecamp_rich_text(html)
    sanitize(html.to_s, tags: BASECAMP_RICH_TEXT_TAGS, attributes: %w[href target rel])
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
end
