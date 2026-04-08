import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { date: String }
  static targets = ["hour"]

  dragover(event) {
    event.preventDefault()
    event.dataTransfer.dropEffect = "move"
  }

  dragenter(event) {
    const hour = event.target.closest(".timeline__hour")
    if (hour) hour.classList.add("timeline__hour--dragover")
  }

  dragleave(event) {
    const hour = event.target.closest(".timeline__hour")
    if (hour && !hour.contains(event.relatedTarget)) {
      hour.classList.remove("timeline__hour--dragover")
    }
  }

  drop(event) {
    event.preventDefault()
    const hour = event.target.closest(".timeline__hour")
    if (!hour) return
    hour.classList.remove("timeline__hour--dragover")

    const taskId = event.dataTransfer.getData("text/plain")
    const card = document.getElementById(taskId)
    if (!card) return

    const assignmentId = card.dataset.taskCardIdValue
    const hourValue = parseInt(hour.dataset.hour)

    // Snap to 15-minute increments based on Y-position within the hour cell
    const rect = hour.getBoundingClientRect()
    const offsetY = event.clientY - rect.top
    const minuteFraction = offsetY / rect.height
    const minute = Math.min(45, Math.round(minuteFraction * 60 / 15) * 15)

    const csrfToken = document.querySelector("meta[name='csrf-token']")?.content
    const body = new URLSearchParams({
      date: this.dateValue,
      hour: hourValue,
      minute: minute
    })

    fetch(`/task_assignments/${assignmentId}/timebox`, {
      method: "PATCH",
      headers: {
        "X-CSRF-Token": csrfToken,
        "Content-Type": "application/x-www-form-urlencoded",
        "Accept": "text/vnd.turbo-stream.html"
      },
      body: body
    })
  }
}
