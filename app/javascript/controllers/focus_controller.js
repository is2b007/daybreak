import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    document.body.classList.add("focus-open")
  }

  disconnect() {
    document.body.classList.remove("focus-open")
  }

  close() {
    const frame = document.getElementById("focus")
    if (frame) frame.innerHTML = ""
    document.body.classList.remove("focus-open")
  }

  keydown(event) {
    if (event.key === "Escape") {
      event.preventDefault()
      this.close()
    }
  }
}
