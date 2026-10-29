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
