import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    sunrisePlay: { type: Boolean, default: false },
    sunsetPlay:  { type: Boolean, default: false },
    redirectUrl: { type: String, default: "" }
  }

  connect() {
    // Entrance fade-in
    this.element.style.opacity = "0"
    requestAnimationFrame(() => {
      this.element.style.transition = "opacity 0.8s ease"
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
    // Play sound
    this.#playAudio("/sounds/sunrise.mp3")

    // Add animation class for background gradient
    this.element.classList.add("ritual--sunrise-animate")

    // Remove animation class after it finishes so subsequent visits don't replay
    this.element.addEventListener("animationend", () => {
      this.element.classList.remove("ritual--sunrise-animate")
    }, { once: true })
  }

  #playSunset() {
    // Play sound
    this.#playAudio("/sounds/sunset.mp3")

    // Add animation class
    this.element.classList.add("ritual--sunset-animate")

    // After 4.5s, navigate home
    const redirectUrl = this.redirectUrlValue
    if (redirectUrl) {
      setTimeout(() => {
        window.location.href = redirectUrl
      }, 4800)
    }
  }

  #playAudio(src) {
    try {
      const audio = new Audio(src)
      audio.volume = 0.7
      audio.play().catch(() => {
        // Autoplay may be blocked — silently fail
      })
    } catch (_e) {
      // Audio not supported
    }
  }
}
