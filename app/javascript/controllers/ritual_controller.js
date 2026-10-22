import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    sunsetPlay:  { type: Boolean, default: false },
    redirectUrl: { type: String, default: "" }
  }

  connect() {
    // The fade is applied as an inline style, so the stylesheet's
    // prefers-reduced-motion rules can't reach it — check the query here instead.
    // Without this, every ritual screen fades in over 2.4s regardless.
    this.reducedMotion = window.matchMedia?.("(prefers-reduced-motion: reduce)")?.matches ?? false

    if (!this.reducedMotion) {
      this.element.style.opacity = "0"
      requestAnimationFrame(() => {
        this.element.style.transition = "opacity 2.4s ease"
        this.element.style.opacity = "1"
      })
    }

    if (this.sunsetPlayValue) {
      this.#playSunset()
    }
  }

  disconnect() {
    clearTimeout(this.redirectTimer)
  }

  // The sky controller draws and scores sunrise/sundown; this only keeps the
  // wrap screen's hand-off back to the week once the sun has set.
  #playSunset() {
    const redirectUrl = this.redirectUrlValue
    if (redirectUrl) {
      // Track the timer so navigating away mid-animation can't yank the user
      // back to the wrap screen from wherever they went next.
      this.redirectTimer = setTimeout(() => {
        window.location.href = redirectUrl
      }, this.reducedMotion ? 600 : 9000)
    }
  }
}
