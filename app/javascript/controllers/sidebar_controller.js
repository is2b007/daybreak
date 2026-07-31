import { Controller } from "@hotwired/stimulus"

const COLLAPSED_KEY = "daybreak:sidebarCollapsed"
// Keep in sync with the responsive breakpoint in application.css, where the side
// columns stop taking grid space and open over the content instead.
const NARROW = "(max-width: 1100px)"

export default class extends Controller {
  static targets = ["toggleBtn"]

  connect() {
    this.narrow = window.matchMedia?.(NARROW)
    this.#applyStoredState()
    this.#syncToggle()

    // Rotating or resizing into a narrow viewport with the sidebar open would
    // leave a drawer sitting on top of the content.
    this.onNarrowChange = (e) => {
      if (e.matches) this.element.classList.add("sb--collapsed")
      else this.#applyStoredState()
      this.#syncToggle()
    }
    this.narrow?.addEventListener("change", this.onNarrowChange)
  }

  disconnect() {
    this.narrow?.removeEventListener("change", this.onNarrowChange)
  }

  toggle() {
    this.element.classList.toggle("sb--collapsed")
    try {
      localStorage.setItem(
        COLLAPSED_KEY,
        this.element.classList.contains("sb--collapsed") ? "1" : "0"
      )
    } catch (_) { /* private mode */ }
    this.#syncToggle()
  }

  /** Narrow viewports always start closed, without clobbering the desktop preference. */
  #applyStoredState() {
    if (this.narrow?.matches) {
      this.element.classList.add("sb--collapsed")
      return
    }

    let stored = null
    try {
      stored = localStorage.getItem(COLLAPSED_KEY)
    } catch (_) { /* private mode */ }
    this.element.classList.toggle("sb--collapsed", stored === "1")
  }

  #syncToggle() {
    if (!this.hasToggleBtnTarget) return
    const collapsed = this.element.classList.contains("sb--collapsed")
    this.toggleBtnTarget.setAttribute("aria-expanded", String(!collapsed))
    const label = collapsed ? "Expand sidebar" : "Collapse sidebar"
    this.toggleBtnTarget.setAttribute("aria-label", label)
    this.toggleBtnTarget.setAttribute("title", label)
  }
}
