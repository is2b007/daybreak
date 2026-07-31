import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { startedAt: String }
  static targets = ["display"]

  connect() {
    const parsed = Date.parse(this.startedAtValue)
    // An unparseable or missing start rendered "NaN:NaN:NaN" once a second.
    this.startTime = Number.isNaN(parsed) ? null : parsed
    this.tick()
    this.interval = setInterval(() => this.tick(), 1000)
  }

  disconnect() {
    if (this.interval) clearInterval(this.interval)
  }

  tick() {
    if (!this.hasDisplayTarget) return
    if (this.startTime == null) {
      this.displayTarget.textContent = "0:00:00"
      return
    }

    // Clamp at zero: a client clock behind the server's put the start in the
    // future and rendered negative minutes and seconds.
    const elapsed = Math.max(0, Math.floor((Date.now() - this.startTime) / 1000))
    const hours = Math.floor(elapsed / 3600)
    const minutes = Math.floor((elapsed % 3600) / 60)
    const seconds = elapsed % 60

    this.displayTarget.textContent =
      `${hours}:${String(minutes).padStart(2, "0")}:${String(seconds).padStart(2, "0")}`
  }
}
