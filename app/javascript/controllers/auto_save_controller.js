import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input"]

  connect() {
    queueMicrotask(() => this.resizeTitle())
  }

  save() {
    clearTimeout(this.timeout)
    this.timeout = setTimeout(() => {
      this.element.requestSubmit()
    }, 2000)
  }

  /** Title is a wrapping textarea; grow height to fit content (caps at max-height CSS). */
  resizeTitle(event) {
    const ta = event?.target ?? this.element.querySelector("textarea.modal__title-input")
    if (!ta || ta.tagName !== "TEXTAREA") return

    ta.style.height = "auto"
    const maxPx = Math.min(window.innerHeight * 0.4, 12 * 16)
    const next = Math.min(ta.scrollHeight, maxPx)
    ta.style.height = `${next}px`
    ta.style.overflowY = ta.scrollHeight > maxPx ? "auto" : "hidden"
  }
}
