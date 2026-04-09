import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.boundHandleEscape = this.handleEscape.bind(this)
    document.addEventListener("keydown", this.boundHandleEscape)
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundHandleEscape)
  }

  close() {
    const frame = document.getElementById("modal")
    if (frame) frame.innerHTML = ""
  }

  closeIfBackdrop(event) {
    if (event.target === this.element) this.close()
  }

  handleEscape(event) {
    if (event.key === "Escape") this.close()
  }
}
