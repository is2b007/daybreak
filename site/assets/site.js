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

// Motion: the hero rises in, the sun climbs from behind the app as you
// scroll, and each section eases up once it's in view. Without Motion (or
// with reduced motion) the page shows everything at rest.
const root = document.documentElement
const Motion = window.Motion
// The head script hides [data-reveal] sections and un-hides them after 2.5s
// unless this block marks itself ready; any failure here shows them at rest.
if (root.classList.contains("motion") && Motion) {
  try {
    const { animate, inView, scroll, stagger } = Motion
    const spring = { type: "spring", stiffness: 140, damping: 22 }

    animate(".hero__copy > *", { opacity: [0, 1], y: [18, 0] }, { ...spring, delay: stagger(0.08) })
    animate(".app", { opacity: [0, 1], y: [48, 0] }, { ...spring, stiffness: 70, delay: 0.45 })
    animate(".sun", { opacity: [0, 1], y: ["45%", "0%"] }, { duration: 2.2, delay: 0.3, ease: [0.2, 0.7, 0.2, 1] })

    const hero = document.querySelector(".hero")
    scroll(animate(".sun", { y: ["0%", "-12%"] }, { ease: "linear" }), { target: hero, offset: ["start start", "end start"] })
    scroll(animate(".app__window", { scale: [0.97, 1] }, { ease: "linear" }), { target: hero, offset: ["start start", "center start"] })

    inView("[data-reveal]", (group) => {
      animate([...group.children], { opacity: [0, 1], y: [28, 0] }, { ...spring, delay: stagger(0.09) })
    }, { amount: 0.2, margin: "0px 0px -8% 0px" })
    root.setAttribute("data-motion-ready", "")
  } catch {
    root.classList.remove("motion")
  }
} else {
  root.classList.remove("motion")
}

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
