// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"

// Not in the apps: Android sends service worker requests without the app's
// user agent, so the server would stop recognising it.
const inApp = /Hotwire Native|Daybreak Desktop/.test(navigator.userAgent)
if ("serviceWorker" in navigator) {
  if (inApp) {
    navigator.serviceWorker.getRegistrations().then(registrations => registrations.forEach(r => r.unregister())).catch(() => {})
  } else {
    navigator.serviceWorker.register("/service-worker.js", { scope: "/" }).catch(() => {})
  }
}

// A screen that takes more than a moment shows the outline of a page instead
// of sitting on the old one (or, in the apps, a spinner).
const SKELETON = `<div class="page-skeleton" aria-hidden="true">
  <div class="page-skeleton__bar page-skeleton__bar--title"></div>
  <div class="page-skeleton__bar page-skeleton__bar--line"></div>
  ${'<div class="page-skeleton__bar page-skeleton__bar--card"></div>'.repeat(5)}
</div>`
let skeletonTimer
const clearSkeleton = () => {
  clearTimeout(skeletonTimer)
  document.querySelectorAll(".page-skeleton").forEach(el => el.remove())
}
document.addEventListener("turbo:visit", event => {
  clearSkeleton()
  // Refreshes of the same page keep it on screen.
  if (event.detail.url === location.href) return
  skeletonTimer = setTimeout(() => {
    document.querySelector(".shell > .mid")?.insertAdjacentHTML("beforeend", SKELETON)
  }, 300)
})
for (const name of ["turbo:render", "turbo:load", "turbo:before-cache", "turbo:fetch-request-error"]) {
  document.addEventListener(name, clearSkeleton)
}

// Adding a to-do replaces the form it was typed in, so after Enter the field
// lost focus and the next one went nowhere. Put the cursor back in the new field.
const QUICK_ADD = ".kanban__quick-add, .day-view__quick-add"
let refocus = null
const restoreQuickAddFocus = () => {
  if (!refocus || Date.now() > refocus.until) return (refocus = null)
  const form = [...document.querySelectorAll(QUICK_ADD)]
    .find(f => f.querySelector("[name=date]")?.value === refocus.date && f.matches(refocus.kind))
  form?.querySelector("input[name=title]")?.focus({ preventScroll: true })
  refocus = null
}
document.addEventListener("turbo:submit-start", ({ target }) => {
  if (!target.matches(QUICK_ADD)) return
  refocus = {
    kind: target.matches(".kanban__quick-add") ? ".kanban__quick-add" : ".day-view__quick-add",
    date: target.querySelector("[name=date]")?.value,
    until: Date.now() + 5000
  }
})
document.addEventListener("turbo:before-stream-render", event => {
  // A refresh re-renders the page later; wait for turbo:render instead.
  if (!refocus || event.target.getAttribute("action") === "refresh") return
  const render = event.detail.render
  event.detail.render = async stream => { await render(stream); restoreQuickAddFocus() }
})
document.addEventListener("turbo:render", restoreQuickAddFocus)

// The Android app tells the page how tall the keyboard is (in screen px), since
// the page itself doesn't shrink for it. Leave room under the focused field
// and bring it into view, so a field low on the page isn't typed into blind.
window.daybreakKeyboard = cssPx => {
  const zoom = document.documentElement.currentCSSZoom || 1
  document.documentElement.style.setProperty("--keyboard", `${cssPx / zoom}px`)
  document.documentElement.toggleAttribute("data-keyboard", cssPx > 0)
  if (cssPx > 0) bringFocusIntoView()
}
const bringFocusIntoView = () => {
  const el = document.activeElement
  if (!el || !el.matches("input, textarea, [contenteditable]")) return
  requestAnimationFrame(() => {
    const bottom = el.getBoundingClientRect().bottom
    const visible = window.innerHeight - (parseFloat(getComputedStyle(document.documentElement).getPropertyValue("--keyboard")) || 0) * (document.documentElement.currentCSSZoom || 1)
    if (bottom > visible - 16) el.scrollIntoView({ block: "center" })
  })
}
document.addEventListener("focusin", () => {
  if (document.documentElement.hasAttribute("data-keyboard")) bringFocusIntoView()
})
