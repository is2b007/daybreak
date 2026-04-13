import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static targets = ["column", "taskList", "sometimeList"]
  static values = { view: String }

  connect() {
    // Drop does not bubble in the DOM; listeners on .kanban__tasks never run when the
    // pointer releases over a child (.task-card, .kanban__empty, etc.). Capture on the
    // sortable root so inbox → day/week drops always hit this controller.
    this._captureDrop = (e) => this.drop(e)
    this._captureDragOver = (e) => this.dragover(e)
    this._captureDragEnter = (e) => this.dragenter(e)
    this._captureDragLeave = (e) => this.dragleave(e)
    this.element.addEventListener("drop", this._captureDrop, true)
    this.element.addEventListener("dragover", this._captureDragOver, true)
    this.element.addEventListener("dragenter", this._captureDragEnter, true)
    this.element.addEventListener("dragleave", this._captureDragLeave, true)
  }

  disconnect() {
    this.element.removeEventListener("drop", this._captureDrop, true)
    this.element.removeEventListener("dragover", this._captureDragOver, true)
    this.element.removeEventListener("dragenter", this._captureDragEnter, true)
    this.element.removeEventListener("dragleave", this._captureDragLeave, true)
  }

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
    const taskList = event.target.closest(".kanban__tasks, .sometime-row")
    if (!taskList) return
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
    const targetList = event.target.closest(".kanban__tasks, .sometime-row")
    if (!targetList) return

    const cardId    = event.dataTransfer.getData("text/plain")
    const dragsrc   = event.dataTransfer.getData("application/x-dragsource")
    const fromInbox = dragsrc === "inbox"
    if (!cardId) return

    // ── HEY email drag branch ────────────────────────────────────────────────
    if (dragsrc === "hey-email" || cardId.startsWith("hey_email_")) {
      event.preventDefault()
      event.stopImmediatePropagation()
      this.clearDragoverStates()

      const emailId = cardId.replace("hey_email_", "")
      const isSometime = targetList.classList.contains("sometime-row")
      const cardContainer = isSometime
        ? (targetList.querySelector(".sometime-row__tasks") || targetList)
        : targetList
      const existingCards = Array.from(cardContainer.querySelectorAll(".task-card"))
      let position = existingCards.length
      for (let i = 0; i < existingCards.length; i++) {
        const r = existingCards[i].getBoundingClientRect()
        if (event.clientY < r.top + r.height / 2) { position = i; break }
      }

      const csrfToken = document.querySelector("meta[name='csrf-token']")?.content
      const body = new URLSearchParams({ position: String(position) })
      if (isSometime) {
        body.set("target_bucket", "sometime")
      } else {
        body.set("target_date", targetList.dataset.date)
        body.set("target_bucket", "day")
      }
      if (this.hasViewValue && this.viewValue === "day") body.set("view", "day")

      fetch(`/hey_emails/${emailId}/plan`, {
        method: "POST",
        headers: {
          "Content-Type": "application/x-www-form-urlencoded",
          "X-CSRF-Token": csrfToken,
          "Accept": "text/vnd.turbo-stream.html"
        },
        body: body.toString()
      }).then(r => r.text()).then(html => {
        if (html) Turbo.renderStreamMessage(html)
      }).catch(err => console.error("hey plan failed", err))
      return
    }
    // ── end HEY email branch ─────────────────────────────────────────────────

    const card = document.getElementById(cardId)
    // Inbox rows use id inbox_task_*; dataTransfer still uses task_<id>
    if (!fromInbox && !card) return

    event.preventDefault()
    event.stopImmediatePropagation()
    this.clearDragoverStates()

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

    if (this.hasViewValue && this.viewValue === "day") {
      body.set("view", "day")
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
    }).catch((err) => console.error("sortable move failed", err))
  }

  clearDragoverStates() {
    document.querySelectorAll(".kanban__tasks--dragover, .sometime-row--dragover").forEach(el => {
      el.classList.remove("kanban__tasks--dragover")
      el.classList.remove("sometime-row--dragover")
    })
  }
}
