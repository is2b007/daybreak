import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["select", "message", "suggest", "suggestLabel"]
  static values  = {
    // When true (onboarding): auto-select the detected timezone on connect.
    // When false (settings):  show a suggestion banner if detected ≠ stored.
    autoSelect: { type: Boolean, default: true },
    stored:     { type: String, default: "" }
  }

  connect() {
    try {
      const detected = Intl.DateTimeFormat().resolvedOptions().timeZone
      if (!detected) return

      if (this.autoSelectValue) {
        // Onboarding: auto-populate the dropdown
        if (this.hasSelectTarget) {
          const match = Array.from(this.selectTarget.options).find(o => o.value === detected)
          if (match) this.selectTarget.value = detected
        }
        if (this.hasMessageTarget) {
          const offset  = new Date().toTimeString().match(/GMT([+-]\d{4})/)?.[1]
          const fmt     = offset ? `GMT${offset.slice(0,3)}:${offset.slice(3)}` : ""
          this.messageTarget.textContent =
            `Looks like you're in ${detected.replace(/_/g, " ")} (${fmt}). Right?`
        }
      } else {
        // Settings: suggest if detected differs from what's stored
        const stored = this.storedValue || (this.hasSelectTarget ? this.selectTarget.value : "")
        if (detected && detected !== stored && this.hasSuggestTarget) {
          if (this.hasSuggestLabelTarget) {
            this.suggestLabelTarget.textContent = detected.replace(/_/g, " ")
          }
          this.suggestTarget.hidden = false
          this.suggestTarget.dataset.detectedTz = detected
        }
      }
    } catch (_e) {
      // Intl not available — user picks manually
    }
  }

  // Called when user clicks "Use this" in the suggest banner
  applyDetected(event) {
    const tz = event.currentTarget.closest("[data-detected-tz]")?.dataset.detectedTz
    if (!tz || !this.hasSelectTarget) return
    const match = Array.from(this.selectTarget.options).find(o => o.value === tz)
    if (match) {
      this.selectTarget.value = tz
      // Dismiss the banner
      if (this.hasSuggestTarget) this.suggestTarget.hidden = true
    }
  }
}
