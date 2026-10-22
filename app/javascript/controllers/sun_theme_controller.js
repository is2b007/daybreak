import { Controller } from "@hotwired/stimulus"

// "Follow the sun": light from 6:00 until an hour after Sundown, dark
// otherwise, in the person's timezone. The server sets the theme on each
// load (User#sun_theme_now, same rule); this flips it on a page left open.
export default class extends Controller {
  static values = { timezone: String, sundown: { type: String, default: "17:00" } }

  connect() {
    this.apply()
    this.timer = setInterval(() => this.apply(), 60_000)
  }

  disconnect() {
    clearInterval(this.timer)
  }

  apply() {
    const root = document.documentElement
    const h = this.#hour()
    const darkFrom = Math.min(22, Math.max(16.5, this.#parse(this.sundownValue) + 1))
    const theme = h >= 6 && h < darkFrom ? "light" : "dark"
    if (root.dataset.theme !== theme) root.dataset.theme = theme
  }

  #hour() {
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

  #parse(hhmm) {
    const [hh, mm] = String(hhmm).split(":").map(Number)
    return (hh || 0) + (mm || 0) / 60
  }
}
