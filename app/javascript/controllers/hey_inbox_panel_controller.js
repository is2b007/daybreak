import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static targets = ["item", "folderSelect", "labelSelect", "count", "empty", "filteredEmpty", "sentinel", "list", "loader"]
  static values = { nextOffset: Number }

  connect() {
    if (!this.hasFolderSelectTarget) return
    this._bulkRemoving = false
    this._awaitingFirstPage = false
    this._loadingMore = false
    this._hasMorePages = true
    this.apply()
    this._maybeObserveSentinel()
    this.element.addEventListener("panel:activated", this._onPanelActivated = () => this.refresh())
  }

  disconnect() {
    if (this._sentinelObserver) this._sentinelObserver.disconnect()
    if (this._onPanelActivated) {
      this.element.removeEventListener("panel:activated", this._onPanelActivated)
    }
  }

  refresh() {
    this.reloadForFilters()
  }

  _maybeObserveSentinel() {
    if (!this.hasSentinelTarget || !this.hasListTarget) return
    this._sentinelObserver = new IntersectionObserver(
      (entries) => {
        if (!entries[0]?.isIntersecting || this._loadingMore) return
        this.loadMore()
      },
      { root: this.listTarget, rootMargin: "0px 0px 120px 0px", threshold: 0 }
    )
    this._sentinelObserver.observe(this.sentinelTarget)
  }

  _finishLoading() {
    this._loadingMore = false
    this._awaitingFirstPage = false
    if (this.hasLoaderTarget) this.loaderTarget.classList.remove("is-loading")
    this.apply()
  }

  loadMore() {
    if (this._loadingMore) return
    if (!this.hasSentinelTarget) {
      this._finishLoading()
      return
    }
    if (!this._hasMorePages) {
      this._finishLoading()
      return
    }

    this._loadingMore = true
    if (this.hasLoaderTarget) this.loaderTarget.classList.add("is-loading")
    const offset = this.nextOffsetValue
    const token = document.querySelector("meta[name='csrf-token']")?.content
    const folder = this.folderSelectTarget.value
    const label = this.hasLabelSelectTarget ? this.labelSelectTarget.value : ""
    const params = new URLSearchParams({ offset: String(offset), folder, label })
    fetch(`/hey_emails/more?${params.toString()}`, {
      headers: { Accept: "application/json", "X-CSRF-Token": token || "" }
    })
      .then((r) => {
        if (!r.ok) throw new Error(`HTTP ${r.status}`)
        return r.json()
      })
      .then((data) => {
        if (data.html) {
          this.sentinelTarget.insertAdjacentHTML("beforebegin", data.html)
          this.nextOffsetValue = data.next_offset
        }
        this._hasMorePages = !!data.has_more
        if (!data.has_more && this._sentinelObserver) this._sentinelObserver.disconnect()
        this.sentinelTarget.hidden = !data.has_more
      })
      .catch(() => {})
      .finally(() => this._finishLoading())
  }

  itemTargetDisconnected() {
    if (this._bulkRemoving) return
    this.apply()
  }

  apply() {
    if (!this.hasFolderSelectTarget) return
    const folder = this.folderSelectTarget.value
    const label = this.hasLabelSelectTarget ? this.labelSelectTarget.value : ""

    let visible = 0
    this.itemTargets.forEach((el) => {
      const folderMatch = el.dataset.folder === folder
      const labelMatch = label === "" || el.dataset.label === label
      const show = folderMatch && labelMatch
      el.hidden = !show
      if (show) visible++
    })

    if (this.hasCountTarget) this.countTarget.textContent = String(visible)

    if (this.hasEmptyTarget) {
      const loading = this._loadingMore || this._awaitingFirstPage
      this.emptyTarget.hidden = visible > 0 || loading
    }

    if (this.hasFilteredEmptyTarget) {
      const totalInFolder = this.itemTargets.filter((el) => el.dataset.folder === folder).length
      this.filteredEmptyTarget.hidden = !(visible === 0 && totalInFolder > 0 && label !== "")
    }
  }

  onFolderChange() {
    this.reloadForFilters()
  }

  onLabelChange() {
    this.reloadForFilters()
  }

  onScroll() {
    if (this._loadingMore || !this._hasMorePages || !this.hasListTarget) return
    const el = this.listTarget
    const nearBottom = el.scrollTop + el.clientHeight >= el.scrollHeight - 100
    if (nearBottom) this.loadMore()
  }

  reloadForFilters() {
    this._bulkRemoving = true
    this.itemTargets.forEach((el) => el.remove())
    this._bulkRemoving = false
    this._awaitingFirstPage = true
    this._loadingMore = false
    this._hasMorePages = true
    this.nextOffsetValue = 0
    if (this.hasSentinelTarget) this.sentinelTarget.hidden = false
    if (this._sentinelObserver && this.hasSentinelTarget) {
      this._sentinelObserver.disconnect()
      this._sentinelObserver.observe(this.sentinelTarget)
    }
    this.apply()
    this.loadMore()
  }

  dragstart(event) {
    const row = event.currentTarget
    const emailId = row.dataset.heyEmailId
    if (!emailId) return

    event.dataTransfer.setData("text/plain", `hey_email_${emailId}`)
    event.dataTransfer.setData("application/x-dragsource", "hey-email")
    event.dataTransfer.effectAllowed = "copyMove"
    row.classList.add("r-item--dragging")
    document.body.classList.add("hey-email-dragging")
  }

  dragend(event) {
    const row = event.currentTarget
    row.classList.remove("r-item--dragging")
    document.body.classList.remove("hey-email-dragging")
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
    if (!cardId?.startsWith("task_")) return

    const card = document.getElementById(cardId)
    if (!card || card.dataset.heyEmailTask !== "true") return

    const taskId = card.dataset.taskCardIdValue
    if (!taskId) return

    const sourceDate = card.closest("[data-date]")?.dataset?.date || ""
    const token = document.querySelector("meta[name='csrf-token']")?.content
    const body = new URLSearchParams()
    if (sourceDate) body.set("source_date", sourceDate)
    if (document.querySelector(".day-view[data-controller~='sortable']")) body.set("view", "day")

    fetch(`/task_assignments/${taskId}/restore_hey_email`, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        "X-CSRF-Token": token,
        Accept: "text/vnd.turbo-stream.html"
      },
      body: body.toString()
    })
      .then((r) => r.text())
      .then((html) => {
        if (html) Turbo.renderStreamMessage(html)
      })
      .catch(() => {})
  }
}
