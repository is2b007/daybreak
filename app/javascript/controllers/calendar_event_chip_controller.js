import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { payload: String }

  dragstart(event) {
    if (!this.hasPayloadValue || !this.payloadValue) return
    event.dataTransfer.setData("application/x-daybreak-calendar-event", this.payloadValue)
    event.dataTransfer.effectAllowed = "copyMove"
  }
}
