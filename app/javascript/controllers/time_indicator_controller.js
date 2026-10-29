import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { timezone: String }
  static targets = ["line", "hour", "minute", "ampm"]

  connect() {
    this.update()
    this.interval = setInterval(() => this.update(), 60_000)
  }

  disconnect() {
    clearInterval(this.interval)
  }

  update() {
    if (!this.hasLineTarget) return

    const now = new Date()
    // Use Intl to get the hour/minute in the user's timezone
    const tz = this.timezoneValue || Intl.DateTimeFormat().resolvedOptions().timeZone
    // hourCycle h23, not hour12:false — the latter formats midnight as "24" in
    // en-US, which then renders as "12pm" in the label below.
    const parts = new Intl.DateTimeFormat("en-US", {
      timeZone: tz, hour: "numeric", minute: "numeric", hourCycle: "h23"
    }).formatToParts(now)

    const hour24 = (parseInt(parts.find(p => p.type === "hour")?.value ?? "0", 10) || 0) % 24
    const minute = parseInt(parts.find(p => p.type === "minute")?.value ?? "0", 10) || 0
    const decimal = hour24 + minute / 60

    const hourStart = 7
    const hourEnd = 22
    if (decimal < hourStart || decimal > hourEnd) {
      this.lineTarget.style.display = "none"
      return
    }

    const offset = decimal - hourStart
    this.lineTarget.style.display = ""
    this.lineTarget.style.top = `calc(var(--timeline-hour) * ${offset.toFixed(4)})`

    // Update the time label
    const h12 = hour24 % 12 || 12
    const ampm = hour24 < 12 ? "am" : "pm"
    const minuteStr = minute.toString().padStart(2, "0")

    if (this.hasHourTarget)  this.hourTarget.textContent  = h12
    if (this.hasMinuteTarget) this.minuteTarget.textContent = minuteStr
    if (this.hasAmpmTarget)  this.ampmTarget.textContent  = ampm

    requestAnimationFrame(() => this._hideCoveredHourLabel())
  }

  // Near the top of an hour the time label lands on that hour's label, and the
  // two printed over each other. The time is more useful, so the hour steps aside.
  _hideCoveredHourLabel() {
    const label = this.lineTarget.querySelector(".timeline__now-label")
    if (!label) return
    const now = label.getBoundingClientRect()
    this.element.querySelectorAll(".timeline__hour-label").forEach(el => {
      el.style.visibility = ""
      // The label stretches to fill its row; measure just the text.
      const range = document.createRange()
      range.selectNodeContents(el)
      const r = range.getBoundingClientRect()
      if (r.top < now.bottom && r.bottom > now.top) el.style.visibility = "hidden"
    })
  }
}
