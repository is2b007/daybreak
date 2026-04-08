import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { theme: String }

  connect() {
    this.applyTheme(this.themeValue || "system")
  }

  toggle(event) {
    const theme = event.target.value
    this.applyTheme(theme)
    document.documentElement.dataset.theme = theme === "system" ? "" : theme
  }

  applyTheme(theme) {
    if (theme === "system") {
      document.documentElement.removeAttribute("data-theme")
    } else {
      document.documentElement.dataset.theme = theme
    }
  }
}
