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
    updateUrl: String,
    startsAt: String,
    endsAt: String,
    date: String
  }

  connect() {
    this._onMove = this._move.bind(this)
    this._onUpDoc = this._finishPointer.bind(this)
    this._dragging = false
    this._mode = null // "move" | "resize-top" | "resize-bottom"
    this.element.style.touchAction = "none"
  }

  disconnect() {
    this._teardownDrag()
  }

  pointerdown(event) {
    if (event.target.closest(".hey-timeline-event__delete")) return
    if (event.target.closest(".hey-timeline-event__resize")) return
    if (this.element.classList.contains("timeline__block--allday")) return

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

    this._preDragStyleAttr = this.element.getAttribute("style") || ""

    const tlRect = tl.getBoundingClientRect()
    const blockRect = this.element.getBoundingClientRect()
    this._mode = mode
    this._dragging = true
    this._pointerMoves = 0
    this._pointerStartY = event.clientY
    this._pxPerHour = this._readPxPerHour(tl)

    // Content-space Y: viewport delta misses scrollTop on overflow-y timelines.
    this._initialTopRel = tl.scrollTop + (blockRect.top - tlRect.top)
    this._initialHeight = blockRect.height

    this._startStartMs = Date.parse(this.startsAtValue)
    this._startEndMs = Date.parse(this.endsAtValue)

    this.element.style.top = `${this._initialTopRel}px`
    this.element.style.height = `${this._initialHeight}px`

    document.addEventListener("pointermove", this._onMove)
    document.addEventListener("pointerup", this._onUpDoc, { once: true })
    document.addEventListener("pointercancel", this._onUpDoc, { once: true })
    this.element.classList.add("timeline__block--dragging")
  }

  _move(event) {
    if (!this._dragging) return
    this._pointerMoves += 1
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

    const residualDy =
      event && event.clientY != null ? Math.abs(event.clientY - this._pointerStartY) : 0
    if (this._pointerMoves === 0 && residualDy < 5) {
      this._revertLayout()
      return
    }

    const tl = this.element.closest(".timeline")
    if (!tl) return

    const pxPerHour = this._readPxPerHour(tl)
    const tlRect = tl.getBoundingClientRect()
    const br = this.element.getBoundingClientRect()
    const relTopViewport = br.top - tlRect.top
    const relTop = tl.scrollTop + relTopViewport
    const relH = br.height

    const startDec = HOUR_START + relTop / pxPerHour
    const endDec = HOUR_START + (relTop + relH) / pxPerHour

    const dateStr = this.dateValue || this._dateFromStartsAt()
    if (!dateStr || Number.isNaN(this._startStartMs) || Number.isNaN(this._startEndMs)) {
      this._revertLayout()
      return
    }

    let startMinFromMidnight = snapMinutesFromMidnight(Math.round(startDec * 60))
    let endMinFromMidnight = snapMinutesFromMidnight(Math.round(endDec * 60))
    if (endMinFromMidnight <= startMinFromMidnight) {
      endMinFromMidnight = startMinFromMidnight + MIN_DURATION_MINUTES
    }
    const durationMinutes = snapDurationMinutes(endMinFromMidnight - startMinFromMidnight)
    endMinFromMidnight = startMinFromMidnight + durationMinutes

    const token = document.querySelector("meta[name='csrf-token']")?.content
    const res = await fetch(this.updateUrlValue, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        Accept: "text/vnd.turbo-stream.html, application/json;q=0.1",
        "X-CSRF-Token": token || ""
      },
      body: JSON.stringify({
        date: dateStr,
        start_minutes_from_midnight: startMinFromMidnight,
        duration_minutes: durationMinutes
      })
    })

    const txt = await res.text()

    if (res.ok) {
      if (txt) Turbo.renderStreamMessage(txt)
      return
    }
    this._revertLayout()
  }

  _revertLayout() {
    if (this._preDragStyleAttr != null) {
      this.element.setAttribute("style", this._preDragStyleAttr)
    } else {
      this.element.style.top = ""
      this.element.style.height = ""
    }
  }

  _dateFromStartsAt() {
    const s = Date.parse(this.startsAtValue)
    if (Number.isNaN(s)) return ""
    const dt = new Date(s)
    const y = dt.getFullYear()
    const mo = String(dt.getMonth() + 1).padStart(2, "0")
    const da = String(dt.getDate()).padStart(2, "0")
    return `${y}-${mo}-${da}`
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

  async delete(event) {
    event.preventDefault()
    event.stopPropagation()
    if (!window.confirm("Remove this calendar event from HEY and Daybreak?")) return

    const token = document.querySelector("meta[name='csrf-token']")?.content
    const res = await fetch(this.updateUrlValue, {
      method: "DELETE",
      headers: {
        Accept: "text/vnd.turbo-stream.html, application/json;q=0.1",
        "X-CSRF-Token": token || ""
      }
    })

    const txt = await res.text()
    if (res.ok) {
      if (txt) Turbo.renderStreamMessage(txt)
    } else {
      window.alert("Could not delete the event. Try again.")
    }
  }
}
