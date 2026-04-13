import { Controller } from "@hotwired/stimulus"

const SAVE_DELAY_MS = 800

const HEY_BADGE_BASE = "jrnl-hey-badge"

// HEY pill = connection + “does HEY match our last save?” only (no autosave / no in-flight verbs).
const heyBadgeSynced = () => ({
  className: `${HEY_BADGE_BASE} jrnl-hey-badge--synced`,
  text: "Synced",
  title: "Your last save matches what’s in HEY Journal for this day."
})

// Connected, no journal row yet (or cleared).
const heyBadgeHeyEmpty = () => ({
  className: `${HEY_BADGE_BASE} jrnl-hey-badge--idle`,
  text: "HEY",
  title: "HEY is connected. Notes you write below are saved here and sent to HEY Journal after each save."
})

// Connected, journal exists, digest not yet aligned with HEY (normal right after save).
const heyBadgeHeyLinked = () => ({
  className: `${HEY_BADGE_BASE} jrnl-hey-badge--idle`,
  text: "HEY",
  title: "HEY is connected. This note is saved in Daybreak; we send each version to HEY Journal automatically."
})

function heyBadgeFromServerState(state) {
  if (state === "synced") return heyBadgeSynced()
  if (state === "pending") return heyBadgeHeyLinked()
  return heyBadgeHeyEmpty()
}

export default class extends Controller {
  static targets = ["editor", "status", "heyBadge"]
  static values = {
    url: String,
    csrf: String,
    statusUrl: { type: String, default: "" }
  }

  connect() {
    this._saveTimer = null
    this._heyStatusTimers = []
    this._lastSaved = this.editorTarget.innerHTML
    if (this.hasHeyBadgeTarget) {
      const el = this.heyBadgeTarget
      this._heyBadgeRest = { className: el.className, text: el.textContent, title: el.title }
    }
    this._applyHeyBadgeRest()
    this._scheduleHeyStatusPolls([900, 2800, 7000])
  }

  disconnect() {
    clearTimeout(this._saveTimer)
    this._clearHeyStatusTimers()
  }

  _clearHeyStatusTimers() {
    (this._heyStatusTimers || []).forEach((id) => clearTimeout(id))
    this._heyStatusTimers = []
  }

  _scheduleHeyStatusPolls(delaysMs) {
    if (!this.statusUrlValue) return
    delaysMs.forEach((ms) => {
      this._heyStatusTimers.push(setTimeout(() => this._refreshHeyBadgeFromServer(), ms))
    })
  }

  async _refreshHeyBadgeFromServer() {
    if (!this.statusUrlValue || !this.hasHeyBadgeTarget) return
    if (this.editorTarget.innerHTML !== this._lastSaved) return

    try {
      const res = await fetch(this.statusUrlValue, {
        headers: { Accept: "application/json" },
        credentials: "same-origin"
      })
      if (!res.ok) return
      const data = await res.json()
      const state = data.state
      if (state !== "synced" && state !== "pending" && state !== "idle") return

      this._heyBadgeRest = heyBadgeFromServerState(state)
      this._applyHeyBadgeRest()
    } catch (_) {
      /* ignore */
    }
  }

  onInput() {
    clearTimeout(this._saveTimer)
    this._showStatus("saving")
    this._saveTimer = setTimeout(() => this._save(), SAVE_DELAY_MS)
  }

  bold()         { this._exec("bold") }
  italic()       { this._exec("italic") }
  strikethrough(){ this._exec("strikeThrough") }
  blockquote()   { this._exec("formatBlock", "blockquote") }
  code()         { this._wrapSelection("code") }
  bulletList()   { this._exec("insertUnorderedList") }
  orderedList()  { this._exec("insertOrderedList") }
  heading()      { this._exec("formatBlock", "h3") }

  link() {
    const sel = window.getSelection()
    if (!sel || sel.isCollapsed) return
    const url = prompt("URL:")
    if (url) this._exec("createLink", url)
  }

  _exec(command, value = null) {
    this.editorTarget.focus()
    document.execCommand(command, false, value)
    this._scheduleAutoSave()
  }

  _wrapSelection(tag) {
    const sel = window.getSelection()
    if (!sel || sel.isCollapsed) return
    const range = sel.getRangeAt(0)
    const el = document.createElement(tag)
    try {
      range.surroundContents(el)
    } catch (_) {
      el.appendChild(range.extractContents())
      range.insertNode(el)
    }
    sel.removeAllRanges()
    this._scheduleAutoSave()
  }

  _scheduleAutoSave() {
    clearTimeout(this._saveTimer)
    this._showStatus("saving")
    this._saveTimer = setTimeout(() => this._save(), SAVE_DELAY_MS)
  }

  _applyHeyBadgeLook({ className, text, title }) {
    if (!this.hasHeyBadgeTarget) return
    const el = this.heyBadgeTarget
    el.className = className
    el.textContent = text
    el.title = title
  }

  _applyHeyBadgeRest() {
    if (!this.hasHeyBadgeTarget || !this._heyBadgeRest) return
    this._applyHeyBadgeLook(this._heyBadgeRest)
  }

  async _save() {
    const content = this.editorTarget.innerHTML
    if (content === this._lastSaved) {
      this._showStatus("")
      return
    }

    try {
      const res = await fetch(this.urlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/x-www-form-urlencoded",
          "X-CSRF-Token": this.csrfValue
        },
        body: new URLSearchParams({ content })
      })

      if (res.ok) {
        if (this.hasHeyBadgeTarget) {
          const host = document.createElement("div")
          host.innerHTML = content
          this._heyBadgeRest = (host.innerText || "").trim() === ""
            ? heyBadgeHeyEmpty()
            : heyBadgeHeyLinked()
        }
        this._lastSaved = content
        this._showStatus("saved")
        this._applyHeyBadgeRest()
        setTimeout(() => this._showStatus(""), 1800)
        if (this.statusUrlValue) {
          this._clearHeyStatusTimers()
          this._scheduleHeyStatusPolls([1800, 4500, 12000])
        }
      } else {
        this._showStatus("error")
      }
    } catch (_) {
      this._showStatus("error")
    }
  }

  _showStatus(state) {
    if (!this.hasStatusTarget) return
    this.statusTarget.dataset.state = state
    this.statusTarget.textContent = state === "saving" ? "Saving…"
      : state === "saved"   ? "Saved"
      : state === "error"   ? "Error"
      : ""
  }
}
