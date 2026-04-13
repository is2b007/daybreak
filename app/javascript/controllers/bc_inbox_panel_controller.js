import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

const EMPTY_PROJECT = "__empty__"

export default class extends Controller {
  static targets = [ "list", "projectSelect", "sortSelect", "count", "item", "filteredEmpty", "loader", "empty" ]
  static values = { nextOffset: { type: Number, default: 20 } }

  connect() {
    this._loadingMore = false
    this._hasMorePages = true
    this.apply()
    this.element.addEventListener("panel:activated", this._onPanelActivated = () => this.refresh())
  }

  disconnect() {
    if (this._onPanelActivated) {
      this.element.removeEventListener("panel:activated", this._onPanelActivated)
    }
  }

  refresh() {
    this.nextOffsetValue = 0
    this._hasMorePages = true
    this._loadingMore = false
    const items = [ ...this.itemTargets ]
    items.forEach(el => el.remove())
    if (this.hasEmptyTarget) this.emptyTarget.hidden = true
    this.loadMore()
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

  onScroll() {
    if (this._loadingMore || !this._hasMorePages || !this.hasListTarget) return
    const el = this.listTarget
    if (el.scrollTop + el.clientHeight >= el.scrollHeight - 100) this.loadMore()
  }

  _finishBcLoad() {
    this._loadingMore = false
    if (this.hasLoaderTarget) this.loaderTarget.classList.remove("is-loading")
    this.apply()
    if (this.hasEmptyTarget) {
      const hasItems = this.itemTargets.length > 0
      this.emptyTarget.hidden = hasItems
    }
  }

  loadMore() {
    if (this._loadingMore) return
    if (!this._hasMorePages) {
      this._finishBcLoad()
      return
    }
    this._loadingMore = true
    if (this.hasLoaderTarget) this.loaderTarget.classList.add("is-loading")
    const offset = this.nextOffsetValue
    const token = document.querySelector("meta[name='csrf-token']")?.content
    fetch(`/sync/basecamp/more?offset=${offset}`, {
      headers: { Accept: "application/json", "X-CSRF-Token": token || "" }
    })
      .then((r) => {
        if (!r.ok) throw new Error(`HTTP ${r.status}`)
        return r.json()
      })
      .then((data) => {
        if (data.html) {
          this.listTarget.insertAdjacentHTML("beforeend", data.html)
          this.nextOffsetValue = data.next_offset
          this.apply()
        }
        this._hasMorePages = !!data.has_more
      })
      .catch(() => {})
      .finally(() => this._finishBcLoad())
  }

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
    const card = cardId ? document.getElementById(cardId) : null
    if (!cardId || fromInbox) return

    if (cardId.startsWith("hey_email_")) return
    if (card?.dataset?.heyEmailTask === "true") {
      const taskId = card.dataset.taskCardIdValue
      if (!taskId) return
      const sourceDate = card.closest("[data-date]")?.dataset?.date || ""
      const body = new URLSearchParams()
      if (sourceDate) body.set("source_date", sourceDate)
      if (document.querySelector(".day-view[data-controller~='sortable']")) body.set("view", "day")
      const csrfToken = document.querySelector("meta[name='csrf-token']")?.content
      fetch(`/task_assignments/${taskId}/restore_hey_email`, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/x-www-form-urlencoded",
          "X-CSRF-Token": csrfToken,
          "Accept": "text/vnd.turbo-stream.html"
        },
        body: body.toString()
      }).then(r => r.text()).then(html => {
        if (html) {
          const { Turbo } = window
          if (Turbo) Turbo.renderStreamMessage(html)
        }
      })
      return
    }

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
      return bc - ac
    }

    const at = this.#ts(a.dataset.plannedStart)
    const bt = this.#ts(b.dataset.plannedStart)
    if (at == null && bt == null) { /* fall through */ }
    else if (at == null) return 1
    else if (bt == null) return -1
    else if (at !== bt) return at - bt
    const ac = this.#ts(a.dataset.createdAt) || 0
    const bc = this.#ts(b.dataset.createdAt) || 0
    return ac - bc
  }

  #ts(iso) {
    if (!iso) return null
    const n = Date.parse(iso)
    return Number.isNaN(n) ? null : n
  }
}
