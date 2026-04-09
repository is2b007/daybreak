import { Controller } from "@hotwired/stimulus"

const COLLAPSED_KEY = "daybreak:sidebarCollapsed"

export default class extends Controller {
  static targets = ["toggleBtn"]

  connect() {
    try {
      if (localStorage.getItem(COLLAPSED_KEY) === "1") {
        this.element.classList.add("sb--collapsed")
      }
    } catch (_) { /* private mode */ }
    this.#syncToggle()
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

  #syncToggle() {
    if (!this.hasToggleBtnTarget) return
    const collapsed = this.element.classList.contains("sb--collapsed")
    this.toggleBtnTarget.setAttribute("aria-expanded", String(!collapsed))
    const label = collapsed ? "Expand sidebar" : "Collapse sidebar"
    this.toggleBtnTarget.setAttribute("aria-label", label)
    this.toggleBtnTarget.setAttribute("title", label)
  }
}
