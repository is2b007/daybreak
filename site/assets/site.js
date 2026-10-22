import { SkyScene } from "./sky.js?v=2"

const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)").matches
const root = document.documentElement

// Elevations the page sky moves between. Text sits straight on the sky only
// where it stays at DAY or brighter, or at NIGHT; the dusk in between happens
// over an empty stretch of page, so no copy is ever on a half-dark sky.
const DAY = 0.66
const NOON = 1
const NIGHT = 0.01

const SKIES = {
  page: { mode: "sunrise", from: DAY, to: DAY, play: false },
  sunrise: { mode: "sunrise", from: 0.7, to: 0.7, play: false },
  sundown: { mode: "sundown", from: 0.1, to: 0.1, play: false }
}

const scenes = new Map()
for (const canvas of document.querySelectorAll("[data-sky]")) {
  const options = SKIES[canvas.dataset.sky]
  if (!options) continue
  const scene = new SkyScene(canvas, { reducedMotion, ...options })
  scene.start()
  // Paint once now, so a sky that starts off screen is never blank
  scene.draw(scene.to, 0)
  scenes.set(canvas, scene)
}
root.classList.add("has-sky")

// The ritual cards only animate while you can see them
const watcher = new IntersectionObserver((entries) => {
  for (const { target, isIntersecting } of entries) {
    const scene = scenes.get(target)
    if (!scene || reducedMotion) continue
    isIntersecting ? scene.resume() : scene.pause()
  }
})
scenes.forEach((_, canvas) => canvas.dataset.sky !== "page" && watcher.observe(canvas))

// The page sky follows the day as you scroll: morning at the top, noon in the
// middle, afternoon by the end of the copy, then sunset and night
const page = scenes.get(document.querySelector('[data-sky="page"]'))
const dusk = document.querySelector("[data-dusk]")
const easeInOut = (t) => (t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2)

function elevationAt(y) {
  // A little slack at both ends keeps copy clear of the dusk while the sky catches up
  const slack = innerHeight * 0.15
  const sunset = dusk.offsetTop + slack
  const night = dusk.offsetTop + dusk.offsetHeight - innerHeight - slack
  if (y >= night) return NIGHT
  if (y >= sunset) return DAY + (NIGHT - DAY) * easeInOut((y - sunset) / Math.max(1, night - sunset))
  return DAY + (NOON - DAY) * Math.sin(Math.PI * Math.min(1, y / Math.max(1, dusk.offsetTop)))
}

let target = elevationAt(scrollY)
let current = target
let gliding = null

function apply(e) {
  page.from = page.to = e
  page.mode = e < 0.45 && scrollY > dusk.offsetTop ? "sundown" : "sunrise"
  root.classList.toggle("is-night", e < 0.35)
  if (reducedMotion) page.draw(e, 0)
}

// Ease toward the scroll position rather than jumping, so the light moves
function glide() {
  current += (target - current) * 0.14
  if (Math.abs(target - current) < 0.0005) current = target
  apply(current)
  gliding = current === target ? null : requestAnimationFrame(glide)
}

function onScroll() {
  target = elevationAt(scrollY)
  if (reducedMotion) return apply((current = target))
  gliding ??= requestAnimationFrame(glide)
}

apply(current)
addEventListener("scroll", onScroll, { passive: true })
addEventListener("resize", onScroll)

// Masthead turns to glass once the page moves
const masthead = document.querySelector("[data-masthead]")
const onMasthead = () => masthead.classList.toggle("is-scrolled", scrollY > 40)
addEventListener("scroll", onMasthead, { passive: true })
onMasthead()

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
