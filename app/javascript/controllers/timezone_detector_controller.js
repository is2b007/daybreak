import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["select", "message"]

  connect() {
    try {
      const detected = Intl.DateTimeFormat().resolvedOptions().timeZone
      if (detected && this.hasSelectTarget) {
        // Find the matching option
        const options = Array.from(this.selectTarget.options)
        const match = options.find(opt => opt.value === detected)
        if (match) {
          this.selectTarget.value = detected
        }
      }
      if (this.hasMessageTarget) {
        const offset = new Date().toTimeString().match(/GMT([+-]\d{4})/)?.[1]
        const formatted = offset ? `GMT${offset.slice(0, 3)}:${offset.slice(3)}` : ""
        this.messageTarget.textContent = `Looks like you're in ${detected.replace(/_/g, " ")} (${formatted}). Right?`
      }
    } catch (e) {
      // Fallback — user picks manually
    }
  }
}
