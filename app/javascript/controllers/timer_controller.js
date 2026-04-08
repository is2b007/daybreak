import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { startedAt: String }
  static targets = ["display"]

  connect() {
    this.startTime = new Date(this.startedAtValue)
    this.tick()
    this.interval = setInterval(() => this.tick(), 1000)
  }

  disconnect() {
    if (this.interval) clearInterval(this.interval)
  }

  tick() {
    const now = new Date()
    const elapsed = Math.floor((now - this.startTime) / 1000)
    const hours = Math.floor(elapsed / 3600)
    const minutes = Math.floor((elapsed % 3600) / 60)
    const seconds = elapsed % 60

    this.displayTarget.textContent =
      `${hours}:${String(minutes).padStart(2, "0")}:${String(seconds).padStart(2, "0")}`
  }
}
