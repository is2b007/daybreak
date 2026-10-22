import { Controller } from "@hotwired/stimulus"

// Bottom tab bar on phones. Inbox and More open the existing right panel and
// sidebar as full-screen sheets, so their contents stay in one place.
export default class extends Controller {
  static targets = ["inbox", "more"]

  inbox() {
    this.#close("sidebar", ".sb")
    this.#controller("right-panel", ".right")?.openSheet()
  }

  more() {
    this.#close("right-panel", ".right")
    const sb = this.#controller("sidebar", ".sb")
    if (sb) sb.toggle()
  }

  #close(identifier, selector) {
    const el = document.querySelector(selector)
    const collapsedClass = identifier === "sidebar" ? "sb--collapsed" : "right--collapsed"
    if (el && !el.classList.contains(collapsedClass)) this.#controller(identifier, selector)?.toggle()
  }

  #controller(identifier, selector) {
    const el = document.querySelector(selector)
    return el && this.application.getControllerForElementAndIdentifier(el, identifier)
  }
}
