import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import {
  snapMinutesFromMidnight,
  snapDurationMinutes,
  MIN_DURATION_MINUTES
} from "timeline_snap"

const HOUR_START = 7

export default class extends Controller {
  static values = {
    assignmentId: Number,
    date: String,
    duration: { type: Number, default: 60 }
  }

  connect() {
    this._onMove = this._move.bind(this)
    this._onUpDoc = this._finishPointer.bind(this)
    this._dragging = false
    this._mode = null
    this.element.style.touchAction = "none"
  }

  disconnect() {
    this._teardownDrag()
  }

  pointerdown(event) {
    if (event.target.closest(".hey-timeline-event__delete")) return
    if (event.target.closest(".hey-timeline-event__resize")) return
    if (event.target.closest(".task-timeline-block__clear")) return
    event.preventDefault()
    this._beginDrag(event, "move")
  }

  resizePointerdown(event) {
    event.preventDefault()
    event.stopPropagation()
    const edge = event.currentTarget.dataset.edge
    if (edge !== "top" && edge !== "bottom") return
    this._beginDrag(event, edge === "top" ? "resize-top" : "resize-bottom")
  }

  _beginDrag(event, mode) {
    const tl = this.element.closest(".timeline")
    if (!tl) return

    const tlRect = tl.getBoundingClientRect()
    const blockRect = this.element.getBoundingClientRect()
    this._mode = mode
    this._dragging = true
    this._pointerStartY = event.clientY
    this._pxPerHour = this._readPxPerHour(tl)

    this._initialTopRel = blockRect.top - tlRect.top
    this._initialHeight = blockRect.height

    this.element.style.top = `${this._initialTopRel}px`
    this.element.style.height = `${this._initialHeight}px`

    document.addEventListener("pointermove", this._onMove)
    document.addEventListener("pointerup", this._onUpDoc, { once: true })
    document.addEventListener("pointercancel", this._onUpDoc, { once: true })
    this.element.classList.add("timeline__block--dragging")
  }

  _move(event) {
    if (!this._dragging) return
    const dy = event.clientY - this._pointerStartY
    const minH = Math.max(this._pxPerHour * 0.25, 12)

    if (this._mode === "move") {
      this.element.style.top = `${Math.max(0, this._initialTopRel + dy)}px`
      return
    }

    if (this._mode === "resize-bottom") {
      const nh = Math.max(minH, this._initialHeight + dy)
      this.element.style.height = `${nh}px`
      return
    }

    if (this._mode === "resize-top") {
      let newTop = this._initialTopRel + dy
      let newH = this._initialHeight - dy
      if (newH < minH) {
        newTop = this._initialTopRel + this._initialHeight - minH
        newH = minH
      }
      if (newTop < 0) {
        newH = Math.max(minH, newH + newTop)
        newTop = 0
      }
      this.element.style.top = `${newTop}px`
      this.element.style.height = `${newH}px`
    }
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

    const tl = this.element.closest(".timeline")
    if (!tl) return

    const pxPerHour = this._readPxPerHour(tl)
    const tlRect = tl.getBoundingClientRect()
    const br = this.element.getBoundingClientRect()
    const relTop = br.top - tlRect.top
    const relH = br.height

    const startDec = HOUR_START + relTop / pxPerHour
    const endDec = HOUR_START + (relTop + relH) / pxPerHour

    let startMinFromMidnight = snapMinutesFromMidnight(Math.round(startDec * 60))
    let endMinFromMidnight = snapMinutesFromMidnight(Math.round(endDec * 60))
    if (endMinFromMidnight <= startMinFromMidnight) {
      endMinFromMidnight = startMinFromMidnight + MIN_DURATION_MINUTES
    }

    const durationMinutes = snapDurationMinutes(endMinFromMidnight - startMinFromMidnight)
    endMinFromMidnight = startMinFromMidnight + durationMinutes

    const hour = Math.floor(startMinFromMidnight / 60) % 24
    const minute = startMinFromMidnight % 60

    const csrfToken = document.querySelector("meta[name='csrf-token']")?.content
    const body = new URLSearchParams({
      date: this.dateValue,
      hour: String(hour),
      minute: String(minute),
      duration_minutes: String(durationMinutes)
    })

    const res = await fetch(`/task_assignments/${this.assignmentIdValue}/timebox`, {
      method: "PATCH",
      headers: {
        "X-CSRF-Token": csrfToken,
        "Content-Type": "application/x-www-form-urlencoded",
        Accept: "text/vnd.turbo-stream.html"
      },
      body
    })

    if (res.ok) {
      const html = await res.text()
      if (html) Turbo.renderStreamMessage(html)
    } else {
      this._revertLayout()
    }
  }

  _revertLayout() {
    this.element.style.top = ""
    this.element.style.height = ""
  }

  _readPxPerHour(timelineEl) {
    const v = parseFloat(getComputedStyle(timelineEl).getPropertyValue("--timeline-hour"))
    return Number.isFinite(v) && v > 0 ? v : 52
  }

  _teardownDrag() {
    document.removeEventListener("pointermove", this._onMove)
    document.removeEventListener("pointerup", this._onUpDoc)
    document.removeEventListener("pointercancel", this._onUpDoc)
  }

  async clear(event) {
    event.preventDefault()
    event.stopPropagation()
    if (!window.confirm("Remove this time from the timeline?")) return

    const csrfToken = document.querySelector("meta[name='csrf-token']")?.content
    const body = new URLSearchParams({ date: this.dateValue, clear: "1" })

    const res = await fetch(`/task_assignments/${this.assignmentIdValue}/timebox`, {
      method: "PATCH",
      headers: {
        "X-CSRF-Token": csrfToken,
        "Content-Type": "application/x-www-form-urlencoded",
        Accept: "text/vnd.turbo-stream.html"
      },
      body
    })

    if (res.ok) {
      const html = await res.text()
      if (html) Turbo.renderStreamMessage(html)
    } else {
      window.alert("Could not clear the timebox.")
    }
  }
}
