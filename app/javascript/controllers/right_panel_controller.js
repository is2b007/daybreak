import { Controller } from "@hotwired/stimulus"

const COLLAPSED_KEY = "daybreak:rightPanelCollapsed"
const WIDTH_KEY = "daybreak:rightPanelContentWidthPx"
const TAB_KEY = "daybreak:rightPanelTab"
// Keep in sync with the responsive breakpoint in application.css, where the side
// columns stop taking grid space and open over the content instead.
const NARROW = "(max-width: 1100px)"

export default class extends Controller {
  static targets = ["tab", "railBtn", "toggleBtn", "content"]

  connect() {
    this.narrow = window.matchMedia?.(NARROW)
    this.#applyStoredState()
    this.#applyStoredWidth()
    this.#applyStoredTab()
    this.#syncToggle()
    this.element.dataset.sheetReady = ""
    this.#expandForSunrisePlan()

    // Rotating or resizing into a narrow viewport with the panel open would leave
    // a drawer sitting on top of the content.
    this.onNarrowChange = (e) => {
      if (e.matches) this.element.classList.add("right--collapsed")
      else this.#applyStoredState()
      this.#syncToggle()
    }
    this.narrow?.addEventListener("change", this.onNarrowChange)
  }

  disconnect() {
    this.narrow?.removeEventListener("change", this.onNarrowChange)
  }

  /** Narrow viewports always start closed, without clobbering the desktop preference. */
  #applyStoredState() {
    if (this.narrow?.matches) {
      this.element.classList.add("right--collapsed")
      return
    }

    let stored = null
    try {
      stored = localStorage.getItem(COLLAPSED_KEY)
    } catch (_) { /* private mode */ }
    // Closed until the person opens it: the week gets the full width by default
    this.element.classList.toggle("right--collapsed", stored !== "0")
  }

  toggle() {
    this.element.classList.toggle("right--collapsed")
    try {
      localStorage.setItem(
        COLLAPSED_KEY,
        this.element.classList.contains("right--collapsed") ? "1" : "0"
      )
    } catch (_) { /* private mode */ }
    this.#syncToggle()
  }

  /** Phone tab bar: open on the inbox last used (Basecamp or HEY), or close if open. */
  openSheet() {
    if (!this.element.classList.contains("right--collapsed")) return this.toggle()
    let tab = null
    try { tab = localStorage.getItem(TAB_KEY) } catch (_) { /* private mode */ }
    this.#activateTab(tab === "hey" ? "hey" : "bc")
    this.toggle()
  }

  /** Rail icons open the panel on their tab; clicking the open tab's icon closes it. */
  switchTab(event) {
    const tab = event.currentTarget.dataset.tab
    const collapsed = this.element.classList.contains("right--collapsed")
    const alreadyOn = event.currentTarget.classList.contains("on")
    if (collapsed || alreadyOn) this.toggle()
    this.#activateTab(tab)
    try { localStorage.setItem(TAB_KEY, tab) } catch (_) { /* private mode */ }
  }

  /** Reopen on the tab you last chose, so ticking a goal doesn't bounce you back to Basecamp. */
  #applyStoredTab() {
    let tab = null
    try { tab = localStorage.getItem(TAB_KEY) } catch (_) { /* private mode */ }
    if (tab && this.tabTargets.some(t => t.dataset.tab === tab)) this.#activateTab(tab)
  }

  /** After Sunrise “Plan today”, open the panel and focus Basecamp inbox for dragging. */
  #expandForSunrisePlan() {
    try {
      const u = new URL(window.location.href)
      if (u.searchParams.get("plan") !== "1") return

      // On a narrow viewport the panel opens as a drawer over the board it is
      // meant to be dragged onto, so leave it closed and just preselect the tab.
      if (!this.narrow?.matches) {
        this.element.classList.remove("right--collapsed")
        localStorage.setItem(COLLAPSED_KEY, "0")
      }
      this.#activateTab("bc")
      this.#syncToggle()

      u.searchParams.delete("plan")
      const q = u.searchParams.toString()
      const next = u.pathname + (q ? `?${q}` : "") + u.hash
      window.history.replaceState({}, "", next)
    } catch (_) { /* private mode / invalid URL */ }
  }

  #activateTab(tabName) {
    this.tabTargets.forEach(t => {
      const active = t.dataset.tab === tabName
      t.classList.toggle("on", active)
      if (active) t.dispatchEvent(new CustomEvent("panel:activated", { bubbles: false }))
    })
    this.railBtnTargets.forEach(b => {
      b.classList.toggle("on", b.dataset.tab === tabName)
    })
  }

  startResize(event) {
    if (this.element.classList.contains("right--collapsed")) return
    if (this._resizing) return
    event.preventDefault()

    this._resizing = true
    this._resizeStartX = event.clientX
    this._resizeStartWidth = this.#readContentWidthPx()

    this._onMove = (e) => this.#onResizeMove(e)
    this._onUp = () => this.#onResizeEnd()

    window.addEventListener("pointermove", this._onMove)
    window.addEventListener("pointerup", this._onUp)
    window.addEventListener("pointercancel", this._onUp)

    this.element.classList.add("right--resizing")
    document.body.style.cursor = "col-resize"
    document.body.style.userSelect = "none"
  }

  #onResizeMove(event) {
    const w = this._resizeStartWidth - (event.clientX - this._resizeStartX)
    this.#setContentWidthPx(w, { persist: false })
  }

  #onResizeEnd() {
    if (!this._resizing) return
    this._resizing = false

    window.removeEventListener("pointermove", this._onMove)
    window.removeEventListener("pointerup", this._onUp)
    window.removeEventListener("pointercancel", this._onUp)
    this._onMove = null
    this._onUp = null

    this.element.classList.remove("right--resizing")
    document.body.style.cursor = ""
    document.body.style.userSelect = ""

    const px = this.#readContentWidthPx()
    this.#setContentWidthPx(px, { persist: true })
  }

  #readContentWidthPx() {
    if (!this.hasContentTarget) return this.#defaultWidthPx()
    return Math.round(this.contentTarget.getBoundingClientRect().width)
  }

  #boundsPx() {
    const rootStyle = getComputedStyle(document.documentElement)
    const min = this.#parseCssLengthToPx(rootStyle.getPropertyValue("--right-panel-content-min").trim(), this.contentTarget)
    const max = this.#parseCssLengthToPx(rootStyle.getPropertyValue("--right-panel-content-max").trim(), this.contentTarget)
    return {
      min: Number.isFinite(min) ? min : 176,
      max: Number.isFinite(max) ? max : 416
    }
  }

  #parseCssLengthToPx(value, el) {
    if (!value) return NaN
    const n = parseFloat(value)
    if (Number.isNaN(n)) return NaN
    if (value.endsWith("rem")) {
      const rootPx = parseFloat(getComputedStyle(document.documentElement).fontSize) || 16
      return n * rootPx
    }
    if (value.endsWith("px")) return n
    if (value.endsWith("%")) {
      if (!el?.parentElement) return NaN
      return (n / 100) * el.parentElement.getBoundingClientRect().width
    }
    return n
  }

  #defaultWidthPx() {
    const rootStyle = getComputedStyle(document.documentElement)
    return Math.round(
      this.#parseCssLengthToPx(
        rootStyle.getPropertyValue("--right-panel-content-width").trim(),
        this.hasContentTarget ? this.contentTarget : null
      ) || 248
    )
  }

  #applyStoredWidth() {
    let px = null
    try {
      const raw = localStorage.getItem(WIDTH_KEY)
      if (raw != null) px = parseInt(raw, 10)
    } catch (_) { /* private mode */ }
    if (px == null || Number.isNaN(px)) px = this.#defaultWidthPx()
    this.#setContentWidthPx(px, { persist: false })
  }

  #setContentWidthPx(px, { persist }) {
    const { min, max } = this.#boundsPx()
    const clamped = Math.min(max, Math.max(min, Math.round(px)))
    this.element.style.setProperty("--right-panel-content-width", `${clamped}px`)
    if (persist) {
      try {
        localStorage.setItem(WIDTH_KEY, String(clamped))
      } catch (_) { /* private mode */ }
    }
  }

  #syncToggle() {
    const collapsed = this.element.classList.contains("right--collapsed")
    if (this.hasToggleBtnTarget) {
      this.toggleBtnTarget.setAttribute("aria-expanded", String(!collapsed))
      const label = collapsed ? "Expand side panel" : "Collapse side panel"
      this.toggleBtnTarget.setAttribute("aria-label", label)
      this.toggleBtnTarget.setAttribute("title", label)
    }
    if (this.hasContentTarget) {
      // inert, not aria-hidden: it also takes the hidden panel's controls out of the tab order
      this.contentTarget.toggleAttribute("inert", collapsed)
      this.contentTarget.removeAttribute("aria-hidden")
    }
  }
}
