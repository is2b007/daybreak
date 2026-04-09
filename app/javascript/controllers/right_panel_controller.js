import { Controller } from "@hotwired/stimulus"

const COLLAPSED_KEY = "daybreak:rightPanelCollapsed"

export default class extends Controller {
  static targets = ["tab", "railBtn", "toggleBtn", "content"]

  connect() {
    try {
      if (localStorage.getItem(COLLAPSED_KEY) === "1") {
        this.element.classList.add("right--collapsed")
      }
    } catch (_) { /* private mode */ }
    this.#syncToggle()
  }

  toggle() {
    this.element.classList.toggle("right--collapsed")
    try {
      localStorage.setItem(
        COLLAPSED_KEY,
        this.element.classList.contains("right--collapsed") ? "1" : "0"
      )
    } catch (_) { /* private mode */ }
    this.#syncToggle()
  }

  switchTab(event) {
    const tabName = event.currentTarget.dataset.tab

    this.tabTargets.forEach(t => {
      t.classList.toggle("on", t.dataset.tab === tabName)
    })

    this.railBtnTargets.forEach(b => {
      b.classList.toggle("on", b.dataset.tab === tabName)
    })
  }

  #syncToggle() {
    const collapsed = this.element.classList.contains("right--collapsed")
    if (this.hasToggleBtnTarget) {
      this.toggleBtnTarget.setAttribute("aria-expanded", String(!collapsed))
      const label = collapsed ? "Expand side panel" : "Collapse side panel"
      this.toggleBtnTarget.setAttribute("aria-label", label)
      this.toggleBtnTarget.setAttribute("title", label)
    }
    if (this.hasContentTarget) {
      this.contentTarget.setAttribute("aria-hidden", collapsed ? "true" : "false")
    }
  }
}
