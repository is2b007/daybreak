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

  handleKeydown(event) {
    if (event.key === " " || event.key === "Enter" || event.key.toLowerCase() === "f") {
      event.preventDefault()
      event.stopPropagation()
      Turbo.visit(`/task_assignments/${this.idValue}/focus`, { frame: "focus" })
    }
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
    if (this.completedValue || this._completing) return
    this._completing = true

    // Set a random rotation that matches what the server will store
    const rotation = Math.floor(Math.random() * 7) - 3
    this.element.style.setProperty("--stamp-rotation", `${rotation}deg`)

    // Inject the stamp SVG if not already present
    this.injectStamp()

    // Trigger the press animation
    this.element.classList.add("task-card--completing")

    // After animation completes, POST and let Turbo Stream handle the swap.
    // The POST must not be gated on animationend alone: if the stamp template is
    // missing, the animation is suppressed, or the element is detached mid-press,
    // the event never fires and the click silently does nothing. A timeout a
    // little past the 400ms press guarantees the write happens either way.
    const finish = () => {
      if (this._completed) return
      this._completed = true
      clearTimeout(this._completeFallback)
      this.element.classList.add("task-card--completed")
      this.postAction(`/task_assignments/${this.idValue}/complete`, { rotation })
    }

    const stamp = this.hasStampTarget ? this.stampTarget : null
    const target = stamp || this.element
    target.addEventListener("animationend", finish, { once: true })
    this._completeFallback = setTimeout(finish, 650)
  }

  disconnect() {
    clearTimeout(this._completeFallback)
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
}
