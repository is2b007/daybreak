import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "preview", "stampPreview"]

  select(event) {
    const button = event.currentTarget
    const stamp = button.dataset.stamp

    // Update hidden input
    this.inputTarget.value = stamp

    // Update visual selection
    this.element.querySelectorAll(".stamp-option").forEach(opt => {
      opt.classList.remove("stamp-option--selected")
      opt.setAttribute("aria-pressed", "false")
    })
    button.classList.add("stamp-option--selected")
    button.setAttribute("aria-pressed", "true")

    // Update preview stamp via turbo or clone
    if (this.hasStampPreviewTarget) {
      this.stampPreviewTarget.innerHTML = button.innerHTML
    }
  }
}
