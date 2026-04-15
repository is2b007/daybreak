import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static values = {
    week: String,
    today: String,
    sunrise: String,
    sundown: String,
    dailyLog: String,
    checkin: String
  }

  connect() {
    this.handleKeydown = this.#onKeydown.bind(this)
    document.addEventListener("keydown", this.handleKeydown)
  }

  disconnect() {
    document.removeEventListener("keydown", this.handleKeydown)
  }

  #onKeydown(event) {
    if (event.metaKey || event.ctrlKey || event.altKey) return
    if (this.#isTyping(event)) return

    const route = this.#routeForKey(event.key)
    if (!route) return

    event.preventDefault()

    // Close focus overlay if open
    const focus = document.getElementById("focus")
    if (focus?.innerHTML?.trim()) {
      focus.innerHTML = ""
    }

    Turbo.visit(route)
  }

  #routeForKey(key) {
    switch (key.toLowerCase()) {
      case "w": return this.weekValue
      case "t": return this.todayValue
      case "s": return this.sunriseValue
      case "d": return this.sundownValue
      case "l": return this.dailyLogValue
      case "c": return this.checkinValue
      default:  return null
    }
  }

  #isTyping(event) {
    const el = event.target
    if (el.tagName === "INPUT" || el.tagName === "TEXTAREA" || el.tagName === "SELECT") return true
    if (el.isContentEditable) return true
    return false
  }
}
