import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["stamp"]

  animate() {
    if (!this.hasStampTarget) return

    this.stampTarget.classList.add("stamp--animating")
    this.stampTarget.addEventListener("animationend", () => {
      this.element.classList.add("task-card--completed")
    }, { once: true })
  }
}
