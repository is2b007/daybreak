import { Controller } from "@hotwired/stimulus"

const COLLAPSED_KEY = "daybreak:rightPanelCollapsed"
const WIDTH_KEY = "daybreak:rightPanelContentWidthPx"

export default class extends Controller {
  static targets = ["tab", "railBtn", "toggleBtn", "content"]

  connect() {
    try {
      if (localStorage.getItem(COLLAPSED_KEY) === "1") {
        this.element.classList.add("right--collapsed")
      }
    } catch (_) { /* private mode */ }
    this.#applyStoredWidth()
    this.#syncToggle()
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

  switchTab(event) {
    const tabName = event.currentTarget.dataset.tab

    this.tabTargets.forEach(t => {
      t.classList.toggle("on", t.dataset.tab === tabName)
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
      this.contentTarget.setAttribute("aria-hidden", collapsed ? "true" : "false")
    }
  }
}
