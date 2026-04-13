import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

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

    const calRaw = event.dataTransfer.getData("application/x-daybreak-calendar-event")
    if (calRaw) {
      this._dropCalendarEvent(event, hour, calRaw)
      return
    }

    const taskId = event.dataTransfer.getData("text/plain")
    const card = document.getElementById(taskId)
    if (!card) return

    const assignmentId = card.dataset.taskCardIdValue
    const hourValue = parseInt(hour.dataset.hour)

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
    }).then(r => {
      if (r.ok) return r.text()
      return ""
    }).then(html => {
      if (html) Turbo.renderStreamMessage(html)
    })
  }

  async _dropCalendarEvent(event, hour, calRaw) {
    let payload
    try {
      payload = JSON.parse(calRaw)
    } catch (_) {
      return
    }

    if (payload.all_day) {
      window.alert("All-day events can’t be rescheduled on the timeline here. Edit them in HEY or Basecamp.")
      return
    }

    if (payload.source === "basecamp") {
      window.alert("Basecamp calendar events are read-only on the Daybreak timeline.")
      return
    }

    if (payload.source !== "hey" || !payload.id) return

    const hourValue = parseInt(hour.dataset.hour)
    const rect = hour.getBoundingClientRect()
    const offsetY = event.clientY - rect.top
    const minuteFraction = offsetY / rect.height
    const minute = Math.min(45, Math.round(minuteFraction * 60 / 15) * 15)

    const csrfToken = document.querySelector("meta[name='csrf-token']")?.content
    const body = new URLSearchParams({
      date: this.dateValue,
      hour: String(hourValue),
      minute: String(minute)
    })

    const res = await fetch(`/calendar_events/${payload.id}/slot`, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        Accept: "application/json",
        "X-CSRF-Token": csrfToken || ""
      },
      body
    })

    if (!res.ok) {
      window.alert("Could not update that calendar event. Try again.")
    }
  }
}
