import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static targets = ["column", "taskList", "sometimeList"]

  dragstart(event) {
    const card = event.target.closest(".task-card")
    if (!card) return

    event.dataTransfer.setData("text/plain", card.id)
    event.dataTransfer.setData("application/x-dragsource", "board")
    event.dataTransfer.effectAllowed = "move"
    card.classList.add("task-card--dragging")

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
    const taskList = event.target.closest(".kanban__tasks, .sometime-row")
    if (taskList) taskList.classList.add("kanban__tasks--dragover")
  }

  dragleave(event) {
    const taskList = event.target.closest(".kanban__tasks, .sometime-row")
    if (taskList && !taskList.contains(event.relatedTarget)) {
      taskList.classList.remove("kanban__tasks--dragover")
    }
  }

  drop(event) {
    event.preventDefault()
    this.clearDragoverStates()

    const cardId = event.dataTransfer.getData("text/plain")   // "task_123"
    const fromInbox = event.dataTransfer.getData("application/x-dragsource") === "inbox"
    const card = document.getElementById(cardId)

    // If not from inbox and card not found, bail
    if (!fromInbox && !card) return

    const targetList = event.target.closest(".kanban__tasks, .sometime-row")
    if (!targetList) return

    const isSometime = targetList.classList.contains("sometime-row")
    const targetDate = isSometime ? null : targetList.dataset.date
    const assignmentId = fromInbox
      ? cardId.replace("task_", "")
      : card.dataset.taskCardIdValue

    // Calculate drop position among existing board cards
    const cardContainer = isSometime
      ? (targetList.querySelector(".sometime-row__tasks") || targetList)
      : targetList
    const existingCards = Array.from(cardContainer.querySelectorAll(".task-card"))
    let position = existingCards.length
    for (let i = 0; i < existingCards.length; i++) {
      const cardRect = existingCards[i].getBoundingClientRect()
      if (event.clientY < cardRect.top + cardRect.height / 2) {
        position = i
        break
      }
    }

    // Move card visually for board→board reorder only
    if (!fromInbox && card) {
      if (position < existingCards.length) {
        cardContainer.insertBefore(card, existingCards[position])
      } else {
        cardContainer.appendChild(card)
      }
    }

    // Persist via PATCH
    const csrfToken = document.querySelector("meta[name='csrf-token']")?.content
    const body = new URLSearchParams({
      position: String(position),
      source_date: this.dragSourceDate || "",
      from_inbox: fromInbox ? "1" : "0"
    })

    if (isSometime) {
      body.set("target_bucket", "sometime")
    } else {
      body.set("target_date", targetDate)
      body.set("target_bucket", "day")
    }

    fetch(`/task_assignments/${assignmentId}/move`, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        "X-CSRF-Token": csrfToken,
        "Accept": "text/vnd.turbo-stream.html"
      },
      body: body.toString()
    }).then(r => r.text()).then(html => {
      if (html) Turbo.renderStreamMessage(html)
    })
  }

  clearDragoverStates() {
    document.querySelectorAll(".kanban__tasks--dragover, .sometime-row--dragover").forEach(el => {
      el.classList.remove("kanban__tasks--dragover")
      el.classList.remove("sometime-row--dragover")
    })
  }
}
