import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { id: Number }
  static targets = ["stamp"]

  cycleSize(event) {
    event.stopPropagation()
    const csrfToken = document.querySelector("meta[name='csrf-token']")?.content
    fetch(`/task_assignments/${this.idValue}/cycle_size`, {
      method: "PATCH",
      headers: {
        "X-CSRF-Token": csrfToken,
        "Accept": "text/vnd.turbo-stream.html"
      }
    })
  }

  complete() {
    const csrfToken = document.querySelector("meta[name='csrf-token']")?.content
    fetch(`/task_assignments/${this.idValue}/complete`, {
      method: "PATCH",
      headers: {
        "X-CSRF-Token": csrfToken,
        "Accept": "text/vnd.turbo-stream.html"
      }
    })
  }
}
