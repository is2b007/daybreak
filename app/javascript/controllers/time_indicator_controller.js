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
    const now = new Date()
    // Use Intl to get the hour/minute in the user's timezone
    const tz = this.timezoneValue || Intl.DateTimeFormat().resolvedOptions().timeZone
    const parts = new Intl.DateTimeFormat("en-US", {
      timeZone: tz, hour: "numeric", minute: "numeric", hour12: false
    }).formatToParts(now)

    const hour24 = parseInt(parts.find(p => p.type === "hour")?.value ?? "0")
    const minute = parseInt(parts.find(p => p.type === "minute")?.value ?? "0")
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
  }
}
