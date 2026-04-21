import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static targets = ["sentinel"]
  static values  = { url: String }

  connect() {
    this._loading = false
    this._observer = new IntersectionObserver(
      (entries) => this._onIntersect(entries),
      {
        root: this.element.querySelector(".kanban"),
        rootMargin: "0px 400px 0px 0px",
        threshold: 0
      }
    )
    if (this.hasSentinelTarget) this._observer.observe(this.sentinelTarget)
  }

  disconnect() {
    this._observer?.disconnect()
  }

  sentinelTargetConnected(el) {
    this._observer?.observe(el)
  }

  _onIntersect(entries) {
    if (!entries[0]?.isIntersecting || this._loading) return
    this._load()
  }

  _load() {
    if (this._loading || !this.hasSentinelTarget) return
    const from = this.sentinelTarget.dataset.infiniteWeekFromValue
    if (!from) return

    this._loading = true
    fetch(`${this.urlValue}?from=${from}`, {
      headers: {
        "Accept": "text/vnd.turbo-stream.html",
        "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content || ""
      }
    })
      .then(r => { if (!r.ok) throw new Error(`HTTP ${r.status}`); return r.text() })
      .then(html => { if (html) Turbo.renderStreamMessage(html) })
      .catch(err => console.error("infinite-week:", err))
      .finally(() => { this._loading = false })
  }
}
