import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input"]

  connect() {
    queueMicrotask(() => this.resizeTitle())
    this.handleSubmitEnd = this.#onSubmitEnd.bind(this)
    this.element.addEventListener("turbo:submit-end", this.handleSubmitEnd)
  }

  disconnect() {
    clearTimeout(this.timeout)
    clearTimeout(this.errorTimeout)
    this.element.removeEventListener("turbo:submit-end", this.handleSubmitEnd)
  }

  save() {
    clearTimeout(this.timeout)
    this.timeout = setTimeout(() => {
      this.element.requestSubmit()
    }, 2000)
  }

  // Cancel the debounce and submit immediately — call on blur or before the
  // form is torn down (e.g. closing the focus overlay) so edits aren't lost.
  flush() {
    clearTimeout(this.timeout)
    if (this.element.tagName === "FORM") {
      this.element.requestSubmit()
    }
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

  // Private

  #onSubmitEnd(event) {
    if (!event.detail.success) {
      this.element.dataset.saveError = "true"
      clearTimeout(this.errorTimeout)
      this.errorTimeout = setTimeout(() => {
        delete this.element.dataset.saveError
      }, 3000)
    }
  }
}
