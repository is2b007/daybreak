import { Controller } from "@hotwired/stimulus"

// Tints the main canvas with the sky for the time of day in the person's
// timezone: dawn, morning, midday, afternoon, golden hour, dusk, night.
// Colours blend between keyframes minute by minute, so there's never a jump.
// Dusk is anchored to the person's Sundown time.
//
// Each keyframe: [top, horizon, glow, sun] as [L%, C, H, alpha].
const LIGHT = {
  night:     [[87, 0.030, 280, 1], [90, 0.028, 300, 1], [96, 0.020, 250, 0.55], [98, 0.010, 260, 0.7]],
  dawn:      [[93, 0.035, 305, 1], [94, 0.060, 45, 1],  [96, 0.090, 65, 0.75], [86, 0.120, 55, 1]],
  morning:   [[96, 0.028, 230, 1], [97.5, 0.028, 85, 1], [99, 0.050, 90, 0.65], [95, 0.085, 90, 1]],
  midday:    [[96.5, 0.030, 225, 1], [98.5, 0.010, 90, 1], [100, 0, 0, 0.5], [96, 0.075, 95, 1]],
  afternoon: [[96, 0.026, 220, 1], [97, 0.040, 75, 1], [98, 0.060, 80, 0.6], [95, 0.090, 85, 1]],
  golden:    [[95, 0.040, 60, 1],  [93, 0.085, 55, 1],  [95, 0.110, 65, 0.75], [84, 0.150, 60, 1]],
  dusk:      [[88, 0.050, 295, 1], [90, 0.075, 20, 1],  [93, 0.090, 30, 0.6], [76, 0.130, 30, 1]]
}

const DARK = {
  night:     [[16, 0.030, 270, 1], [20, 0.035, 285, 1], [38, 0.040, 260, 0.35], [82, 0.020, 260, 0.4]],
  dawn:      [[22, 0.045, 295, 1], [30, 0.075, 40, 1],  [48, 0.110, 55, 0.4], [74, 0.140, 55, 1]],
  morning:   [[25, 0.040, 240, 1], [28, 0.040, 70, 1],  [44, 0.060, 80, 0.3], [86, 0.080, 90, 1]],
  midday:    [[26, 0.040, 235, 1], [27, 0.025, 220, 1], [44, 0.040, 220, 0.25], [90, 0.050, 95, 1]],
  afternoon: [[25, 0.035, 230, 1], [28, 0.045, 70, 1],  [44, 0.070, 70, 0.3], [83, 0.100, 80, 1]],
  golden:    [[23, 0.045, 50, 1],  [30, 0.085, 45, 1],  [48, 0.120, 55, 0.4], [72, 0.160, 55, 1]],
  dusk:      [[19, 0.050, 290, 1], [25, 0.075, 15, 1],  [40, 0.095, 20, 0.35], [62, 0.150, 30, 1]]
}

export default class extends Controller {
  static values = { timezone: String, sundown: { type: String, default: "17:00" } }

  connect() {
    this.dark = window.matchMedia("(prefers-color-scheme: dark)")
    this.onScheme = () => this.paint()
    this.dark.addEventListener?.("change", this.onScheme)
    this.paint()
    this.timer = setInterval(() => this.paint(), 60_000)
  }

  disconnect() {
    clearInterval(this.timer)
    this.dark.removeEventListener?.("change", this.onScheme)
  }

  paint() {
    const h = this.#hour()
    const frames = this.#keyframes()
    let i = frames.findIndex(([t]) => t > h)
    if (i <= 0) i = frames.length - 1
    const [t0, a] = frames[i - 1]
    const [t1, b] = frames[i]
    const k = t1 === t0 ? 0 : (h - t0) / (t1 - t0)
    const ease = k * k * (3 - 2 * k)
    this.#followTheSun(h)
    const pal = this.#isDark() ? DARK : LIGHT
    const [top, horizon, glow] = [0, 1, 2].map(n => this.#mix(pal[a][n], pal[b][n], ease))
    // Ever so faint: a hint of where the sun is, never a shape that competes with the cards.
    const sun = this.#mix(pal[a][3], pal[b][3], ease, 0.28)
    const halo = this.#mix(pal[a][3], pal[b][3], ease, 0.1)

    const s = this.element.style
    s.setProperty("--amb-top", top)
    s.setProperty("--amb-horizon", horizon)
    s.setProperty("--amb-glow", glow)
    s.setProperty("--amb-sun", sun)
    s.setProperty("--amb-halo", halo)

    // Sun (or moon) travels an arc across the canvas.
    const sundown = this.#sundown()
    const day = Math.min(1, Math.max(0, (h - 6) / (sundown + 0.5 - 6)))
    const isNight = h < 5.5 || h > sundown + 1.5
    const nightSpan = 24 - (sundown + 1.5) + 5.5
    const p = isNight ? (((h - (sundown + 1.5)) + 24) % 24) / nightSpan : day
    // Low in the sky the disc sits on the horizon and looks bigger; at noon it's small and high.
    const elevation = Math.sin(Math.PI * p)
    // The moon keeps to the quieter right-hand side, clear of today's column.
    s.setProperty("--amb-sun-x", isNight ? `${62 + 30 * p}%` : `${10 + 80 * p}%`)
    s.setProperty("--amb-sun-y", isNight ? `${70 - 45 * elevation}%` : `${104 - 78 * elevation}%`)
    s.setProperty("--amb-sun-r", `${Math.round((isNight ? 34 : 64) - (isNight ? 6 : 22) * elevation)}px`)
    s.setProperty("--amb-stars", isNight ? "1" : "0")
    this.element.dataset.ambientPhase = a
  }

  // "Follow the sun" theme: the page is light by day and dark at night.
  // Same rule as User#sun_theme_now, so a reload never flips it back.
  #followTheSun(h) {
    const root = document.documentElement
    if (root.dataset.themeMode !== "sun") return
    const darkFrom = Math.min(22, Math.max(16.5, this.#parse(this.sundownValue) + 1))
    const theme = h >= 6 && h < darkFrom ? "light" : "dark"
    if (root.dataset.theme !== theme) root.dataset.theme = theme
  }

  #keyframes() {
    const d = this.#sundown()
    return [
      [0, "night"], [5, "night"], [6.25, "dawn"], [8.5, "morning"], [12, "midday"],
      [14.5, "afternoon"], [Math.max(15, d - 1), "golden"], [d + 0.5, "dusk"],
      [Math.min(23.5, d + 2), "night"], [24, "night"]
    ]
  }

  #hour() {
    const override = new URLSearchParams(location.search).get("ambient_at")
    if (override) return this.#parse(override)
    try {
      const parts = new Intl.DateTimeFormat("en-GB", {
        timeZone: this.timezoneValue || undefined, hour: "2-digit", minute: "2-digit", hourCycle: "h23"
      }).formatToParts(new Date())
      const get = (t) => Number(parts.find(p => p.type === t).value)
      return get("hour") + get("minute") / 60
    } catch (_) {
      const n = new Date()
      return n.getHours() + n.getMinutes() / 60
    }
  }

  #sundown() {
    return Math.min(21, Math.max(15.5, this.#parse(this.sundownValue)))
  }

  #parse(hhmm) {
    const [hh, mm] = String(hhmm).split(":").map(Number)
    return (hh || 0) + (mm || 0) / 60
  }

  #isDark() {
    const t = document.documentElement.dataset.theme
    if (t === "dark") return true
    if (t === "light") return false
    return this.dark.matches
  }

  #mix(a, b, k, alphaScale = 1) {
    let dh = b[2] - a[2]
    if (Math.abs(dh) > 180) dh -= Math.sign(dh) * 360
    // Grey ends (chroma 0) have no hue; borrow the other end's.
    const h = a[1] === 0 ? b[2] : b[1] === 0 ? a[2] : a[2] + dh * k
    const v = (n) => a[n] + (b[n] - a[n]) * k
    return `oklch(${v(0).toFixed(2)}% ${v(1).toFixed(4)} ${((h % 360) + 360) % 360} / ${(v(3) * alphaScale).toFixed(3)})`
  }
}
