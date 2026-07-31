import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { name: String, timezone: String }
  static targets = ["text"]

  connect() {
    if (!this.hasTextTarget) return

    const now = new Date()
    // Use timezone if available.
    // hourCycle h23, not hour12:false — the latter formats midnight as "24" in
    // en-US, which fell past every branch below and greeted "Good evening" at 1am.
    let hour = now.getHours()
    if (this.timezoneValue) {
      try {
        const formatted = new Intl.DateTimeFormat("en-US", {
          hour: "numeric",
          hourCycle: "h23",
          timeZone: this.timezoneValue
        }).format(now)
        const parsed = parseInt(formatted, 10)
        if (Number.isFinite(parsed)) hour = parsed % 24
      } catch (e) { /* fallback to local */ }
    }

    let greeting
    if (hour < 12) greeting = "Good morning"
    else if (hour < 17) greeting = "Good afternoon"
    else greeting = "Good evening"

    this.textTarget.textContent = `${greeting}, ${this.nameValue}.`
  }
}
