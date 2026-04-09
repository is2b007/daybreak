import { Controller } from "@hotwired/stimulus"

const EMPTY_PROJECT = "__empty__"

export default class extends Controller {
  static targets = [ "list", "projectSelect", "sortSelect", "count", "item", "filteredEmpty" ]

  connect() {
    this.apply()
  }

  apply() {
    if (!this.hasListTarget || !this.hasProjectSelectTarget || !this.hasSortSelectTarget) return

    const items = [ ...this.itemTargets ]
    const sortKey = this.sortSelectTarget.value
    const project = this.projectSelectTarget.value

    items.sort((a, b) => this.#compare(a, b, sortKey))
    items.forEach((el) => this.listTarget.appendChild(el))

    let visible = 0
    for (const el of items) {
      const pn = el.dataset.projectName ?? ""
      const match =
        project === "" ||
        (project === EMPTY_PROJECT ? pn === "" : pn === project)
      el.hidden = !match
      if (match) visible += 1
    }

    if (this.hasCountTarget) this.countTarget.textContent = String(visible)

    if (this.hasFilteredEmptyTarget) {
      this.filteredEmptyTarget.hidden = !(items.length > 0 && visible === 0)
    }
  }

  #compare(a, b, sortKey) {
    if (sortKey === "project") {
      const ap = a.dataset.projectName || "\uffff"
      const bp = b.dataset.projectName || "\uffff"
      const c = ap.localeCompare(bp, undefined, { sensitivity: "base" })
      if (c !== 0) return c
      return (a.dataset.title || "").localeCompare(b.dataset.title || "", undefined, { sensitivity: "base" })
    }

    if (sortKey === "size") {
      const as = Number(a.dataset.sizeRank ?? 0)
      const bs = Number(b.dataset.sizeRank ?? 0)
      if (as !== bs) return as - bs
      return (a.dataset.title || "").localeCompare(b.dataset.title || "", undefined, { sensitivity: "base" })
    }

    // due_date: planned_start_at then created_at
    const at = this.#ts(a.dataset.plannedStart)
    const bt = this.#ts(b.dataset.plannedStart)
    if (at !== bt) {
      if (at == null && bt == null) { /* fall through */ }
      else if (at == null) return 1
      else if (bt == null) return -1
      else if (at !== bt) return at - bt
    }
    const ac = this.#ts(a.dataset.createdAt) || 0
    const bc = this.#ts(b.dataset.createdAt) || 0
    if (ac !== bc) return ac - bc
    return (a.dataset.title || "").localeCompare(b.dataset.title || "", undefined, { sensitivity: "base" })
  }

  #ts(iso) {
    if (!iso) return null
    const n = Date.parse(iso)
    return Number.isNaN(n) ? null : n
  }
}
