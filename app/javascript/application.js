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
