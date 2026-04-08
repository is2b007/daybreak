import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    // Trigger entrance animation
    this.element.style.opacity = "0"
    requestAnimationFrame(() => {
      this.element.style.transition = "opacity 0.8s ease"
      this.element.style.opacity = "1"
    })
  }
}
