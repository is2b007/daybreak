import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["column", "taskList", "sometimeList"]

  dragstart(event) {
    const card = event.target.closest(".task-card")
    if (!card) return

    event.dataTransfer.setData("text/plain", card.id)
    event.dataTransfer.effectAllowed = "move"
    card.classList.add("task-card--dragging")

    // Store source info
    this.dragSourceDate = card.closest("[data-date]")?.dataset.date
  }

  dragend(event) {
    const card = event.target.closest(".task-card")
    if (card) card.classList.remove("task-card--dragging")
    this.clearDragoverStates()
  }

  dragover(event) {
    event.preventDefault()
    event.dataTransfer.dropEffect = "move"
  }

  dragenter(event) {
    const taskList = event.target.closest(".kanban__tasks, .sometime-row__tasks")
    if (taskList) taskList.classList.add("kanban__tasks--dragover")
  }

  dragleave(event) {
    const taskList = event.target.closest(".kanban__tasks, .sometime-row__tasks")
    if (taskList && !taskList.contains(event.relatedTarget)) {
      taskList.classList.remove("kanban__tasks--dragover")
    }
  }

  drop(event) {
    event.preventDefault()
    this.clearDragoverStates()

    const taskId = event.dataTransfer.getData("text/plain")
    const card = document.getElementById(taskId)
    if (!card) return

    const targetList = event.target.closest(".kanban__tasks, .sometime-row__tasks")
    if (!targetList) return

    const targetDate = targetList.dataset.date
    const assignmentId = card.dataset.taskCardIdValue

    // Calculate position
    const cards = Array.from(targetList.querySelectorAll(".task-card"))
    const rect = event.clientY
    let position = cards.length
    for (let i = 0; i < cards.length; i++) {
      const cardRect = cards[i].getBoundingClientRect()
      if (rect < cardRect.top + cardRect.height / 2) {
        position = i
        break
      }
    }

    // Move card visually
    if (position < cards.length) {
      targetList.insertBefore(card, cards[position])
    } else {
      targetList.appendChild(card)
    }

    // Persist via PATCH
    const csrfToken = document.querySelector("meta[name='csrf-token']")?.content
    fetch(`/task_assignments/${assignmentId}/move`, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        "X-CSRF-Token": csrfToken,
        "Accept": "text/vnd.turbo-stream.html"
      },
      body: `target_date=${targetDate}&position=${position}&source_date=${this.dragSourceDate || ""}`
    })
  }

  clearDragoverStates() {
    document.querySelectorAll(".kanban__tasks--dragover").forEach(el => {
      el.classList.remove("kanban__tasks--dragover")
    })
  }
}
