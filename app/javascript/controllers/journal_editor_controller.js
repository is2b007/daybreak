import { Controller } from "@hotwired/stimulus"

const SAVE_DELAY_MS = 800

export default class extends Controller {
  static targets = ["editor", "status"]
  static values = { url: String, csrf: String }

  connect() {
    this._saveTimer = null
    this._lastSaved = this.editorTarget.innerHTML
  }

  disconnect() {
    clearTimeout(this._saveTimer)
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
        this._lastSaved = content
        this._showStatus("saved")
        setTimeout(() => this._showStatus(""), 1800)
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
