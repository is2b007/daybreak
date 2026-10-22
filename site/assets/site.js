import { SkyScene } from "./sky.js"

const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)").matches

// Each canvas gets its own slice of the day. The hero rises on arrival; the
// ritual cards and the self-host band hold their sky and only loop ambiently.
const SKIES = {
  hero: { mode: "sunrise", from: 0.18, to: 0.86 },
  sunrise: { mode: "sunrise", from: 0.5, to: 0.5, play: false },
  sundown: { mode: "sundown", from: 0.1, to: 0.1, play: false },
  night: { mode: "sundown", from: 0.02, to: 0.02, play: false }
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

// Masthead settles onto the page once the hero scrolls away
const masthead = document.querySelector("[data-masthead]")
const onScroll = () => masthead.classList.toggle("is-scrolled", scrollY > 40)
addEventListener("scroll", onScroll, { passive: true })
onScroll()

// Copy buttons
for (const button of document.querySelectorAll("[data-copy]")) {
  button.addEventListener("click", async () => {
    const text = document.querySelector(button.dataset.copy).textContent
    try {
      await navigator.clipboard.writeText(text)
      button.textContent = "Copied"
    } catch {
      getSelection().selectAllChildren(document.querySelector(button.dataset.copy))
      button.textContent = "Selected"
    }
    setTimeout(() => (button.textContent = "Copy"), 1600)
  })
}
