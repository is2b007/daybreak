import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    updateUrl: String,
    startsAt: String,
    endsAt: String
  }

  connect() {
    this._onMove = this._move.bind(this)
    this._onUpDoc = this._finishPointer.bind(this)
    this._dragging = false
    this.element.style.touchAction = "none"
  }

  disconnect() {
    this._teardownDrag()
  }

  pointerdown(event) {
    if (event.target.closest(".hey-timeline-event__delete")) return
    event.preventDefault()
    this._dragging = true
    this._startY = event.clientY
    this._startTop = parseFloat(this.element.style.top) || 0
    document.addEventListener("pointermove", this._onMove)
    document.addEventListener("pointerup", this._onUpDoc, { once: true })
    document.addEventListener("pointercancel", this._onUpDoc, { once: true })
    this.element.classList.add("timeline__block--dragging")
  }

  _move(event) {
    if (!this._dragging) return
    const dy = event.clientY - this._startY
    this.element.style.top = `${Math.max(0, this._startTop + dy)}px`
  }

  _finishPointer(event) {
    document.removeEventListener("pointermove", this._onMove)
    this._up(event)
  }

  async _up(event) {
    if (!this._dragging) return
    this._dragging = false
    this.element.classList.remove("timeline__block--dragging")
    document.removeEventListener("pointermove", this._onMove)

    const pxPerHour = parseFloat(
      getComputedStyle(this.element.closest(".timeline")).getPropertyValue("--timeline-hour")
    ) || 52
    const dy = event.clientY - this._startY
    const hoursDelta = dy / pxPerHour

    const startMs = Date.parse(this.startsAtValue)
    const endMs = Date.parse(this.endsAtValue)
    if (Number.isNaN(startMs) || Number.isNaN(endMs)) return

    const durationMs = endMs - startMs
    const newStart = new Date(startMs + hoursDelta * 3600000)
    const newEnd = new Date(newStart.getTime() + durationMs)

    const token = document.querySelector("meta[name='csrf-token']")?.content
    const res = await fetch(this.updateUrlValue, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
        "X-CSRF-Token": token || ""
      },
      body: JSON.stringify({
        starts_at: newStart.toISOString(),
        ends_at: newEnd.toISOString()
      })
    })

    if (!res.ok) {
      this.element.style.top = `${this._startTop}px`
    }
  }

  _teardownDrag() {
    document.removeEventListener("pointermove", this._onMove)
    document.removeEventListener("pointerup", this._onUpDoc)
    document.removeEventListener("pointercancel", this._onUpDoc)
  }

  async delete(event) {
    event.preventDefault()
    event.stopPropagation()
    if (!window.confirm("Remove this calendar event from HEY and Daybreak?")) return

    const token = document.querySelector("meta[name='csrf-token']")?.content
    const res = await fetch(this.updateUrlValue, {
      method: "DELETE",
      headers: {
        Accept: "application/json",
        "X-CSRF-Token": token || ""
      }
    })

    if (!res.ok) {
      window.alert("Could not delete the event. Try again.")
    }
  }
}
