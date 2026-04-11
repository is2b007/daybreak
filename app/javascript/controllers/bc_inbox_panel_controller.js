import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

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

<<<<<<< HEAD
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
=======
  dragover(event) {
    event.preventDefault()
    event.dataTransfer.dropEffect = "move"
    this.listTarget.classList.add("r-list--dragover")
  }

  dragleave(event) {
    if (!this.listTarget.contains(event.relatedTarget)) {
      this.listTarget.classList.remove("r-list--dragover")
    }
  }

  drop(event) {
    event.preventDefault()
    this.listTarget.classList.remove("r-list--dragover")

    const cardId = event.dataTransfer.getData("text/plain")
    const fromInbox = event.dataTransfer.getData("application/x-dragsource") === "inbox"
    if (!cardId || fromInbox) return  // ignore inbox-to-inbox drags

    const assignmentId = cardId.replace("task_", "")
    const csrfToken = document.querySelector("meta[name='csrf-token']")?.content

    fetch(`/task_assignments/${assignmentId}/move`, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        "X-CSRF-Token": csrfToken,
        "Accept": "text/vnd.turbo-stream.html"
      },
      body: new URLSearchParams({ target_bucket: "inbox" }).toString()
    }).then(r => r.text()).then(html => {
      if (html) {
        const { Turbo } = window
        if (Turbo) Turbo.renderStreamMessage(html)
      }
    })
  }

  dragstart(event) {
    const item = event.target.closest(".r-item")
    if (!item) return
    const taskId = item.dataset.taskId
    if (!taskId) return
    event.dataTransfer.setData("text/plain", `task_${taskId}`)
    event.dataTransfer.setData("application/x-dragsource", "inbox")
    event.dataTransfer.effectAllowed = "move"
    this.dragging = true
    item.classList.add("r-item--dragging")
    document.body.classList.add("inbox-dragging")
  }

  dragend(event) {
    const item = event.target.closest(".r-item")
    if (item) item.classList.remove("r-item--dragging")
    document.body.classList.remove("inbox-dragging")
    setTimeout(() => { this.dragging = false }, 0)
  }

  openModal(event) {
    if (this.dragging) return
    if (event.defaultPrevented) return
    if (event.target.closest("button, a, input, select, textarea, label, [role='button']")) return

    const item = event.currentTarget.closest(".r-item")
    const taskId = item?.dataset.taskId
    if (!taskId) return

    Turbo.visit(`/task_assignments/${taskId}`, { frame: "modal" })
  }

  #compare(a, b, sortKey) {
    if (sortKey === "alphabetical") {
      return (a.dataset.title || "").localeCompare(b.dataset.title || "", undefined, { sensitivity: "base" })
    }

    if (sortKey === "recently_created") {
      const ac = this.#ts(a.dataset.createdAt) || 0
      const bc = this.#ts(b.dataset.createdAt) || 0
      return bc - ac  // newest first
    }

    // due_date: planned_start_at (nulls last), then created_at
    const at = this.#ts(a.dataset.plannedStart)
    const bt = this.#ts(b.dataset.plannedStart)
    if (at == null && bt == null) { /* fall through */ }
    else if (at == null) return 1
    else if (bt == null) return -1
    else if (at !== bt) return at - bt
    const ac = this.#ts(a.dataset.createdAt) || 0
    const bc = this.#ts(b.dataset.createdAt) || 0
    return ac - bc
>>>>>>> cursor/collapsible-panels-and-week-topbar
  }

  #ts(iso) {
    if (!iso) return null
    const n = Date.parse(iso)
    return Number.isNaN(n) ? null : n
  }
}
