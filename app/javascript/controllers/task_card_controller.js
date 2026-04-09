import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static values = { id: Number, completed: Boolean }
  static targets = ["stamp"]

  openModal(event) {
    if (this.#isInteractiveClick(event)) return
    if (event.defaultPrevented) return

    Turbo.visit(`/task_assignments/${this.idValue}`, { frame: "modal" })
  }

  cycleSize(event) {
    event.stopPropagation()
    this.postAction(`/task_assignments/${this.idValue}/cycle_size`)
  }

  complete() {
    this.postAction(`/task_assignments/${this.idValue}/complete`)
  }

  animateThenComplete(event) {
    event.preventDefault()
    event.stopPropagation()
    if (this.completedValue) return

    // Set a random rotation that matches what the server will store
    const rotation = Math.floor(Math.random() * 7) - 3
    this.element.style.setProperty("--stamp-rotation", `${rotation}deg`)

    // Inject the stamp SVG if not already present
    this.injectStamp()

    // Trigger the press animation
    this.element.classList.add("task-card--completing")

    // After animation completes, POST and let Turbo Stream handle the swap
    const stamp = this.hasStampTarget ? this.stampTarget : null
    const target = stamp || this.element

    target.addEventListener("animationend", () => {
      this.element.classList.add("task-card--completed")
      this.postAction(`/task_assignments/${this.idValue}/complete`, { rotation })
    }, { once: true })
  }

  injectStamp() {
    if (this.hasStampTarget) return
    const template = document.querySelector("[data-user-stamp-svg]")
    if (!template) return

    const stamp = document.createElement("div")
    stamp.className = "task-card__stamp"
    stamp.dataset.taskCardTarget = "stamp"
    stamp.innerHTML = template.innerHTML
    this.element.appendChild(stamp)
  }

  postAction(url, body = null) {
    const csrfToken = document.querySelector("meta[name='csrf-token']")?.content
    const headers = {
      "X-CSRF-Token": csrfToken,
      "Accept": "text/vnd.turbo-stream.html"
    }

    const options = { method: "PATCH", headers }

    if (body) {
      headers["Content-Type"] = "application/json"
      options.body = JSON.stringify(body)
    }

    fetch(url, options)
      .then(r => r.text())
      .then(html => { if (html) Turbo.renderStreamMessage(html) })
  }

  #isInteractiveClick(event) {
    const interactive = event.target.closest("button, a, input, select, textarea, label, [role='button']")
    return !!interactive
  }

  #isInteractiveClick(event) {
    const interactive = event.target.closest("button, a, input, select, textarea, label, [role='button']")
    return !!interactive
  }
}
