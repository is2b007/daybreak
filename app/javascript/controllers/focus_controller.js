import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    document.body.classList.add("focus-open")
  }

  disconnect() {
    document.body.classList.remove("focus-open")
  }

  close() {
    // Flush any pending auto-save before we rip out the frame — otherwise the
    // 2-second debounce drops notes typed right before closing.
    this.#flushAutoSaves()
    const frame = document.getElementById("focus")
    if (frame) frame.innerHTML = ""
    document.body.classList.remove("focus-open")
  }

  keydown(event) {
    if (event.key === "Escape") {
      event.preventDefault()
      this.close()
    }
  }

  switchTab(event) {
    const name = event.params.tab
    if (!name) return
    this.element.querySelectorAll(".focus__tab").forEach((btn) => {
      const match = btn.dataset.focusTabParam === name
      btn.classList.toggle("focus__tab--active", match)
      btn.setAttribute("aria-selected", match ? "true" : "false")
    })
    this.element.querySelectorAll("[data-focus-panel]").forEach((panel) => {
      const match = panel.dataset.focusPanel === name
      panel.classList.toggle("focus__panel--active", match)
      panel.hidden = !match
    })
  }

  #flushAutoSaves() {
    const app = window.Stimulus
    if (!app) return
    this.element.querySelectorAll("[data-controller~='auto-save']").forEach((el) => {
      const controller = app.getControllerForElementAndIdentifier(el, "auto-save")
      if (controller && typeof controller.flush === "function") controller.flush()
    })
  }
}
