import { Controller } from "@hotwired/stimulus"

// Copies the text content of an element identified by ID to the system clipboard.
// Briefly flashes a "Copied" label on the button, then restores it.
export default class extends Controller {
  static targets = ["icon", "label"]

  async copy(event) {
    const sourceId = event.params.source
    const el = document.getElementById(sourceId)
    if (!el) return

    try {
      await navigator.clipboard.writeText(el.textContent.trim())
      this.#flash(sourceId)
    } catch {
      // Fallback for browsers where clipboard API is blocked.
      const range = document.createRange()
      range.selectNodeContents(el)
      const sel = window.getSelection()
      sel.removeAllRanges()
      sel.addRange(range)
      document.execCommand("copy")
      sel.removeAllRanges()
      this.#flash(sourceId)
    }
  }

  #flash(id) {
    const labels = this.labelTargets.filter(el => el.dataset.id === id)
    const icons  = this.iconTargets.filter(el => el.dataset.id === id)

    labels.forEach(el => { el.textContent = "Copied!" })
    icons.forEach(el => { el.innerHTML = this.#checkSvg() })

    setTimeout(() => {
      labels.forEach(el => { el.textContent = "Copy" })
      icons.forEach(el => { el.innerHTML = this.#copySvg() })
    }, 1800)
  }

  #checkSvg() {
    return `<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><polyline points="2,9 6,13 14,4"/></svg>`
  }

  #copySvg() {
    return `<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="4" y="4" width="9" height="11" rx="1.5"/><path d="M4 4V3a1 1 0 0 1 1-1h6a1 1 0 0 1 1 1v1"/></svg>`
  }
}
