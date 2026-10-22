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

    // The sky controller draws and scores sunrise/sundown; this only hands the
    // wrap screen back to the week. It always does, even when the sunset already
    // played today (a second close used to strand you on the wrap). Track the
    // timer so navigating away mid-animation can't yank the user back.
    if (this.redirectUrlValue) {
      const delay = this.reducedMotion ? 600 : (this.sunsetPlayValue ? 9000 : 1800)
      this.redirectTimer = setTimeout(() => {
        window.location.href = this.redirectUrlValue
      }, delay)
    }
  }

  disconnect() {
    clearTimeout(this.redirectTimer)
  }
}
