import { Controller } from "@hotwired/stimulus"

const ORDER = ["system", "light", "dark"]
const ICONS = {
  system: '<svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2"><rect x="2" y="3" width="20" height="14" rx="2"/><line x1="8" y1="21" x2="16" y2="21"/><line x1="12" y1="17" x2="12" y2="21"/></svg>',
  light:  '<svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="5"/><line x1="12" y1="1" x2="12" y2="3"/><line x1="12" y1="21" x2="12" y2="23"/><line x1="4.22" y1="4.22" x2="5.64" y2="5.64"/><line x1="18.36" y1="18.36" x2="19.78" y2="19.78"/><line x1="1" y1="12" x2="3" y2="12"/><line x1="21" y1="12" x2="23" y2="12"/><line x1="4.22" y1="19.78" x2="5.64" y2="18.36"/><line x1="18.36" y1="5.64" x2="19.78" y2="4.22"/></svg>',
  dark:   '<svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/></svg>'
}

export default class extends Controller {
  static values = { theme: String }
  static targets = ["icon"]

  connect() {
    this.applyTheme(this.themeValue || "system")
    this.updateIcon()
  }

  cycle() {
    const current = this.themeValue || "system"
    const next = ORDER[(ORDER.indexOf(current) + 1) % ORDER.length]
    this.themeValue = next
    this.applyTheme(next)
    this.updateIcon()
    this.persist(next)
  }

  applyTheme(theme) {
    const root = document.documentElement
    if (theme === "system") {
      root.removeAttribute("data-theme")
    } else {
      root.dataset.theme = theme
    }
  }

  updateIcon() {
    if (!this.hasIconTarget) return
    this.iconTarget.innerHTML = ICONS[this.themeValue || "system"]
  }

  applyFromRadio(event) {
    const theme = event.target.dataset.theme
    this.themeValue = theme
    this.applyTheme(theme)
    this.updateIcon()
  }

  persist(theme) {
    const csrfToken = document.querySelector("meta[name='csrf-token']")?.content
    fetch("/settings", {
      method: "PATCH",
      headers: {
        "X-CSRF-Token": csrfToken,
        "Content-Type": "application/json",
        "Accept": "application/json"
      },
      body: JSON.stringify({ user: { theme: theme } })
    })
  }
}
