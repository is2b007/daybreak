import { Controller } from "@hotwired/stimulus"

// Handles the inbox sync buttons: POST silently, spin the icon, refresh the panel in place.
// No page reload, no flash message.
export default class extends Controller {
  static values = {
    url:   String,   // POST endpoint, e.g. /sync/hey
    panel: String    // Stimulus identifier of the panel to refresh, e.g. "hey-inbox-panel"
  }

  #busy = false

  async sync() {
    if (this.#busy) return
    this.#busy = true
    this.element.classList.add("r-sync-btn--loading")

    try {
      const token = document.querySelector('meta[name="csrf-token"]')?.content
      await fetch(this.urlValue, {
        method:  "POST",
        headers: { "X-CSRF-Token": token, "Accept": "application/json" }
      })
    } catch (_e) {
      // Network failure — still try to refresh whatever we have locally
    }

    // Hand off to the panel controller so it reloads items from the DB
    const id    = this.panelValue
    const panel = id && document.querySelector(`[data-controller~="${id}"]`)
    if (panel) {
      const ctrl = this.application.getControllerForElementAndIdentifier(panel, id)
      ctrl?.refresh()
    }

    this.element.classList.remove("r-sync-btn--loading")
    this.#busy = false
  }
}
