import { Controller } from "@hotwired/stimulus"

// Opens the week with today as the first column in view, so the days left
// this week are what you see; the days already gone sit to the left.
export default class extends Controller {
  static targets = ["board"]

  connect() {
    const today = this.boardTarget.querySelector(".kanban__column--today")
    if (!today) return
    const column = today.closest("turbo-frame") || today
    this.boardTarget.scrollLeft = Math.min(column.offsetLeft - this.boardTarget.offsetLeft, this.boardTarget.scrollWidth - this.boardTarget.clientWidth)
  }
}
