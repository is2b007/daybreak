import { Controller } from "@hotwired/stimulus"
import { SkyScene } from "sky/scene"
import { soundEnabled, setSoundEnabled } from "sky/sound"
import { OnboardingSound } from "sky/onboarding_sound"

const IDLE_AFTER = 45_000

// Onboarding is one long sunrise. The sky starts at night and the sun climbs
// a little with every step; each step's words drift in, the pad moves to a
// new chord and a bell rings. Steps load into a Turbo Frame, so this
// controller (and the sound) lives across them.
//
// Each step's root element says how high the sun should be:
//   <section data-onboarding-step="3" data-elevation="0.6" data-moment="sunrise">
export default class extends Controller {
  static targets = ["canvas", "frame", "progress", "soundToggle", "card", "stamper"]

  connect() {
    this.reducedMotion = window.matchMedia?.("(prefers-reduced-motion: reduce)")?.matches ?? false
    this.element.classList.add("onb--ready")
    if (this.reducedMotion) this.element.classList.add("onb--still")

    this.sound = new OnboardingSound()
    const step = this.currentStep()
    const elevation = this.elevationOf(step)
    // Arriving mid-way (a refresh, or back from connecting HEY): rise gently into place
    this.scene = new SkyScene(this.canvasTarget, {
      mode: "sunrise",
      from: Math.max(0, elevation - 0.08),
      to: elevation,
      reducedMotion: this.reducedMotion
    })
    this.scene.duration = 2400
    this.scene.start()

    this.applyStep(step, { initial: true })

    this.beforeRender = this.beforeRender.bind(this)
    this.afterRender = this.afterRender.bind(this)
    this.frameTarget.addEventListener("turbo:before-frame-render", this.beforeRender)
    this.frameTarget.addEventListener("turbo:frame-render", this.afterRender)

    // Browsers only allow sound after a gesture: start on the first one
    this.unlock = this.unlock.bind(this)
    // (a touch pointerdown is not an activation gesture, so listen for click/touchend)
    for (const type of ["click", "touchend", "keydown"]) document.addEventListener(type, this.unlock, true)
    this.renderSoundToggle()

    // Someone who wanders off shouldn't come back to a pad still going at full
    // strength: after a while without input the sound settles to a murmur
    this.wake = this.wake.bind(this)
    for (const type of ["pointerdown", "keydown"]) document.addEventListener(type, this.wake, true)
    this.wake()
  }

  wake() {
    clearTimeout(this.idleTimer)
    if (this.idle) {
      this.idle = false
      this.sound.settle(false)
    }
    this.idleTimer = setTimeout(() => {
      this.idle = true
      this.sound.settle(true)
    }, IDLE_AFTER)
  }

  disconnect() {
    this.frameTarget.removeEventListener("turbo:before-frame-render", this.beforeRender)
    this.frameTarget.removeEventListener("turbo:frame-render", this.afterRender)
    this.removeUnlock()
    for (const type of ["pointerdown", "keydown"]) document.removeEventListener(type, this.wake, true)
    clearTimeout(this.idleTimer)
    this.scene?.destroy()
    this.sound?.close()
  }

  // Sound ----------------------------------------------------------------

  async unlock() {
    if (!soundEnabled()) return this.removeUnlock()
    const step = this.currentStep()
    if (!(await this.sound.start(step?.number ?? 1))) return // try again on the next gesture
    this.removeUnlock()
    // Muted while start() was waiting for the context to resume
    if (!soundEnabled()) this.sound.stop()
    this.renderSoundToggle()
  }

  removeUnlock() {
    for (const type of ["click", "touchend", "keydown"]) document.removeEventListener(type, this.unlock, true)
  }

  async toggleSound() {
    const on = !soundEnabled()
    setSoundEnabled(on)
    if (on) {
      await this.sound.start(this.currentStep()?.number ?? 1)
    } else {
      this.sound.stop()
    }
    this.renderSoundToggle()
  }

  renderSoundToggle() {
    if (!this.hasSoundToggleTarget) return
    const on = soundEnabled()
    this.soundToggleTarget.setAttribute("aria-pressed", String(on))
    this.soundToggleTarget.title = on ? "Sound on" : "Sound off"
    this.soundToggleTarget.classList.toggle("sky__button--off", !on)
  }

  type(event) {
    if (event.key?.length === 1 || event.key === "Backspace") this.sound.tick()
  }

  // Runs after stamp-picker has swapped the new stamp into the sample card:
  // the rubber stamp drops in, and the ink and thud land on impact
  stamp() {
    if (!this.hasCardTarget || this.reducedMotion) {
      this.sound.stamp()
      return
    }
    const card = this.cardTarget
    const ink = card.querySelector(".onb__card-stamp .stamp")
    if (ink && this.hasStamperTarget) {
      this.stamperTarget.style.setProperty("--stamper-ink", getComputedStyle(ink).color)
    }
    clearTimeout(this.inkTimer)
    card.classList.remove("is-stamping", "is-inked")
    void card.offsetWidth // restart the animations on a quick second pick
    card.classList.add("is-stamping")
    this.inkTimer = setTimeout(() => {
      card.classList.add("is-inked")
      this.sound.stamp()
    }, 400)
  }

  // Steps ----------------------------------------------------------------

  // Hold Turbo's swap until the current words have drifted away
  beforeRender(event) {
    if (this.reducedMotion) return
    const step = this.currentStep()
    if (!step) return
    event.preventDefault()
    step.element.classList.add("is-leaving")
    setTimeout(() => event.detail.resume(), 420)
  }

  afterRender() {
    const step = this.currentStep()
    if (step) this.applyStep(step)
  }

  applyStep(step, { initial = false } = {}) {
    if (!step) return
    const previous = this.lastElevation ?? step.elevation
    const climb = step.elevation - previous
    this.lastElevation = step.elevation

    this.renderProgress(step.number)
    // A big climb is the sun coming up: let the sky move before the words arrive
    const rising = !initial && Math.abs(climb) > 0.2
    const tone = step.elevation < 0.4 ? "night" : "day"
    clearTimeout(this.toneTimer)
    // Flip light/dark text about when the sky crosses from dusk to day
    this.toneTimer = setTimeout(() => (this.element.dataset.tone = tone), rising && !this.reducedMotion ? 1700 : 0)

    if (!initial) {
      this.scene.glideTo(step.elevation, rising ? 3200 : 1800)
      this.sound.setStep(step.number)
      if (rising && climb > 0) this.sound.flourish({ delay: 0.4 })
      else this.sound.chime(step.number, { delay: 0.25 })
      if (step.element.dataset.moment === "morning") this.sound.flourish({ delay: 0.6 })
      this.reveal(step.element, rising && !this.reducedMotion ? 1900 : 150)
    } else {
      this.reveal(step.element, 500)
    }
  }

  // Words rise out of a blur one by one; everything else follows in order
  reveal(root, startDelay) {
    let t = startDelay
    root.querySelectorAll("[data-reveal]").forEach((el) => {
      if (el.dataset.reveal === "words") {
        for (const word of this.splitWords(el)) {
          word.style.setProperty("--d", `${t}ms`)
          t += 75
        }
        t += 260
      } else {
        el.style.setProperty("--d", `${t}ms`)
        t += 170
      }
    })
    root.classList.add("is-in")
    setTimeout(() => this.focus(root), this.reducedMotion ? 0 : Math.min(t, 1800))
  }

  splitWords(el) {
    if (el.dataset.split) return el.querySelectorAll(".onb__word")
    el.dataset.split = "true"
    const walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT)
    const nodes = []
    while (walker.nextNode()) nodes.push(walker.currentNode)
    for (const node of nodes) {
      const parts = node.textContent.split(/(\s+)/)
      const fragment = document.createDocumentFragment()
      for (const part of parts) {
        if (!part) continue
        if (/^\s+$/.test(part)) {
          fragment.append(part)
        } else {
          const span = document.createElement("span")
          span.className = "onb__word"
          span.textContent = part
          fragment.append(span)
        }
      }
      node.replaceWith(fragment)
    }
    return el.querySelectorAll(".onb__word")
  }

  // Frame swaps don't honour autofocus, and a screen reader should hear the new step
  focus(root) {
    if (!root.isConnected) return
    const target = root.querySelector("[autofocus]") || root.querySelector("h1")
    target?.focus({ preventScroll: true })
  }

  renderProgress(number) {
    this.progressTargets.forEach((dot, i) => {
      dot.classList.toggle("is-done", i + 1 < number)
      dot.classList.toggle("is-current", i + 1 === number)
      if (i + 1 === number) dot.setAttribute("aria-current", "step")
      else dot.removeAttribute("aria-current")
    })
  }

  // The last step leaves the frame for the week view: let the morning settle first
  finish(event) {
    if (this.finishing) return
    event.preventDefault()
    this.finishing = true
    const form = event.target
    this.scene.glideTo(1, 1400)
    this.sound.chime(9)
    this.element.classList.add("onb--leaving")
    setTimeout(() => {
      this.sound.stop(1)
      form.submit()
    }, this.reducedMotion ? 0 : 1400)
  }

  currentStep() {
    const element = this.frameTarget.querySelector("[data-onboarding-step]")
    if (!element) return null
    return {
      element,
      number: parseInt(element.dataset.onboardingStep, 10),
      elevation: parseFloat(element.dataset.elevation)
    }
  }

  elevationOf(step) {
    return step?.elevation ?? 0
  }
}
