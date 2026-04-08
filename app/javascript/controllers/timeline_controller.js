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
    if (hour) hour.style.background = "var(--color-accent-light)"
  }

  dragleave(event) {
    const hour = event.target.closest(".timeline__hour")
    if (hour && !hour.contains(event.relatedTarget)) {
      hour.style.background = ""
    }
  }

  drop(event) {
    event.preventDefault()
    const hour = event.target.closest(".timeline__hour")
    if (hour) hour.style.background = ""

    const taskId = event.dataTransfer.getData("text/plain")
    const card = document.getElementById(taskId)
    if (!card || !hour) return

    const hourValue = parseInt(hour.dataset.hour)
    const assignmentId = card.dataset.taskCardIdValue

    // TODO: Create timebox — POST to create HEY Calendar todo or local timeline block
    console.log(`Timebox task ${assignmentId} at ${hourValue}:00 on ${this.dateValue}`)
  }
}
