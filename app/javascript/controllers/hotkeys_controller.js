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

    // Panel toggles: "<" opens/closes the left sidebar, ">" the right panel.
    if (event.key === "<" || event.key === ">") {
      const identifier = event.key === "<" ? "sidebar" : "right-panel"
      if (this.#togglePanel(identifier)) event.preventDefault()
      return
    }

    // "f" on a hovered task card opens focus mode without needing keyboard focus.
    if (event.key.toLowerCase() === "f" && this.#openHoveredTaskFocus()) {
      event.preventDefault()
      return
    }

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

  #openHoveredTaskFocus() {
    // Pick the innermost hovered task card (task-cards don't nest in practice,
    // but NodeList last() is cheap insurance).
    const hovered = document.querySelectorAll(".task-card:hover")
    const card = hovered[hovered.length - 1]
    if (!card) return false
    const id = card.dataset.taskCardIdValue
    if (!id) return false
    Turbo.visit(`/task_assignments/${id}/focus`, { frame: "focus" })
    return true
  }

  #togglePanel(identifier) {
    const el = document.querySelector(`[data-controller~="${identifier}"]`)
    if (!el) return false
    const controller = window.Stimulus?.getControllerForElementAndIdentifier(el, identifier)
    if (!controller || typeof controller.toggle !== "function") return false
    controller.toggle()
    return true
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
