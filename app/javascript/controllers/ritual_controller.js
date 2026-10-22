import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    sunrisePlay: { type: Boolean, default: false },
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

    if (this.sunrisePlayValue) {
      this.#playSunrise()
    }

    if (this.sunsetPlayValue) {
      this.#playSunset()
    }

    // Closing the day always lands back on the week, even when the sunset
    // already played today (a second close used to strand you on the wrap).
    // Track the timer so navigating away mid-animation can't yank the user back.
    if (this.redirectUrlValue) {
      const delay = this.sunsetPlayValue && !this.reducedMotion ? 4800 : 1800
      this.redirectTimer = setTimeout(() => {
        window.location.href = this.redirectUrlValue
      }, delay)
    }
  }

  disconnect() {
    clearTimeout(this.redirectTimer)
  }

  #playSunrise() {
    this.#playAudioFaded("/sounds/sunrise.mp3")
    if (this.reducedMotion) return

    this.element.classList.add("ritual--sunrise-animate")
    this.element.addEventListener("animationend", () => {
      this.element.classList.remove("ritual--sunrise-animate")
    }, { once: true })
  }

  #playSunset() {
    this.#playAudioFaded("/sounds/sunset.mp3")
    if (!this.reducedMotion) this.element.classList.add("ritual--sunset-animate")
  }

  #playAudioFaded(src) {
    try {
      const audio = new Audio(src)
      audio.volume = 0
      const target = 0.6
      const fadeMs = 1200
      const steps = 24
      const stepMs = fadeMs / steps
      let step = 0
      audio.play().then(() => {
        const fade = setInterval(() => {
          step += 1
          audio.volume = Math.min(target, (target * step) / steps)
          if (step >= steps) clearInterval(fade)
        }, stepMs)
      }).catch(() => {
        // Autoplay may be blocked — silently fail
      })
    } catch (_e) {
      // Audio not supported
    }
  }
}
