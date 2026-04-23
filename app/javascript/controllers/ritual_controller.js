import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    sunrisePlay: { type: Boolean, default: false },
    sunsetPlay:  { type: Boolean, default: false },
    redirectUrl: { type: String, default: "" }
  }

  connect() {
    this.element.style.opacity = "0"
    requestAnimationFrame(() => {
      this.element.style.transition = "opacity 2.4s ease"
      this.element.style.opacity = "1"
    })

    if (this.sunrisePlayValue) {
      this.#playSunrise()
    }

    if (this.sunsetPlayValue) {
      this.#playSunset()
    }
  }

  #playSunrise() {
    this.#playAudioFaded("/sounds/sunrise.mp3")
    this.element.classList.add("ritual--sunrise-animate")
    this.element.addEventListener("animationend", () => {
      this.element.classList.remove("ritual--sunrise-animate")
    }, { once: true })
  }

  #playSunset() {
    this.#playAudioFaded("/sounds/sunset.mp3")
    this.element.classList.add("ritual--sunset-animate")

    const redirectUrl = this.redirectUrlValue
    if (redirectUrl) {
      setTimeout(() => {
        window.location.href = redirectUrl
      }, 4800)
    }
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
