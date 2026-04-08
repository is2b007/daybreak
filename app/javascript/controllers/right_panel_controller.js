import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tab", "railBtn"]

  switchTab(event) {
    const tabName = event.currentTarget.dataset.tab

    this.tabTargets.forEach(t => {
      t.classList.toggle("on", t.dataset.tab === tabName)
    })

    this.railBtnTargets.forEach(b => {
      b.classList.toggle("on", b.dataset.tab === tabName)
    })
  }
}
