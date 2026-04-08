import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.createStars(40)
  }

  createStars(count) {
    for (let i = 0; i < count; i++) {
      const star = document.createElement("div")
      star.classList.add("star-dot")
      star.style.left = `${Math.random() * 100}%`
      star.style.top = `${Math.random() * 100}%`
      star.style.animationDelay = `${Math.random() * 3}s`
      star.style.animationDuration = `${1.5 + Math.random() * 2}s`
      this.element.appendChild(star)
    }
  }

  disconnect() {
    this.element.querySelectorAll(".star-dot").forEach(star => star.remove())
  }
}
