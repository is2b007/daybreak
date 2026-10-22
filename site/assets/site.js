import { SkyScene } from "./sky.js?v=3"

const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)").matches

// Each canvas holds one time of day. The hero eases from early to full
// morning once; the rest hold their sky and only loop ambiently. Every
// elevation here keeps the text on it above WCAG AA.
const SKIES = {
  sunrise: { mode: "sunrise", from: 0.66, to: 0.86 },
  "card-sunrise": { mode: "sunrise", from: 0.72, to: 0.72, play: false },
  "card-sundown": { mode: "sundown", from: 0.1, to: 0.1, play: false },
  night: { mode: "sundown", from: 0.01, to: 0.01, play: false }
}

const scenes = new Map()
for (const canvas of document.querySelectorAll("[data-sky]")) {
  const options = SKIES[canvas.dataset.sky]
  if (!options) continue
  const scene = new SkyScene(canvas, { reducedMotion, ...options })
  scene.start()
  // Paint once now, so a sky that starts off screen is never blank
  scene.draw(scene.play ? scene.from : scene.to, 0)
  scenes.set(canvas, scene)
}

// Only animate the skies you can see
const watcher = new IntersectionObserver((entries) => {
  for (const { target, isIntersecting } of entries) {
    const scene = scenes.get(target)
    if (!scene || reducedMotion) continue
    isIntersecting ? scene.resume() : scene.pause()
  }
})
scenes.forEach((_, canvas) => watcher.observe(canvas))

// Masthead: glass once you scroll, dark glass once it's over the night
const masthead = document.querySelector("[data-masthead]")
const sunset = document.querySelector(".sunset")
function onScroll() {
  masthead.classList.toggle("is-scrolled", scrollY > 40)
  masthead.classList.toggle("is-night", sunset.getBoundingClientRect().top + sunset.offsetHeight * 0.6 < masthead.offsetHeight)
}
addEventListener("scroll", onScroll, { passive: true })
onScroll()

// Copy buttons
for (const button of document.querySelectorAll("[data-copy]")) {
  button.addEventListener("click", async () => {
    const source = document.querySelector(button.dataset.copy)
    try {
      await navigator.clipboard.writeText(source.textContent)
      button.textContent = "Copied"
    } catch {
      getSelection().selectAllChildren(source)
      button.textContent = "Selected"
    }
    setTimeout(() => (button.textContent = "Copy"), 1600)
  })
}
