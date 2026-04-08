import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { name: String, timezone: String }
  static targets = ["text"]

  connect() {
    if (!this.hasTextTarget) return

    const now = new Date()
    // Use timezone if available
    let hour = now.getHours()
    if (this.timezoneValue) {
      try {
        const formatted = new Intl.DateTimeFormat("en-US", {
          hour: "numeric",
          hour12: false,
          timeZone: this.timezoneValue
        }).format(now)
        hour = parseInt(formatted)
      } catch (e) { /* fallback to local */ }
    }

    let greeting
    if (hour < 12) greeting = "Good morning"
    else if (hour < 17) greeting = "Good afternoon"
    else greeting = "Good evening"

    this.textTarget.textContent = `${greeting}, ${this.nameValue}.`
  }
}
