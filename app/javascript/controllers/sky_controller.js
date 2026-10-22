import { Controller } from "@hotwired/stimulus"
import { SkyScene } from "sky/scene"
import { RitualSound, soundEnabled, setSoundEnabled } from "sky/sound"

// Animated sky for sunrise and sundown. `play` is true the first time a
// ritual opens today: the sun rises or sets with sound. Otherwise the sky
// rests in its settled state with only the ambient loop.
export default class extends Controller {
  static targets = ["canvas", "soundToggle"]
  static values = {
    mode: { type: String, default: "sunrise" },
    play: { type: Boolean, default: false }
  }

  connect() {
    // Turbo restores cached snapshots on Back and shows them as previews;
    // neither should replay the sunrise.
    if (document.documentElement.hasAttribute("data-turbo-preview")) this.playValue = false
    this.reducedMotion = window.matchMedia?.("(prefers-reduced-motion: reduce)")?.matches ?? false
    this.sound = new RitualSound()
    this.scene = new SkyScene(this.canvasTarget, {
      mode: this.modeValue,
      play: this.playValue,
      reducedMotion: this.reducedMotion
    })
    this.scene.start()
    this.renderSoundToggle()
    if (this.playValue && soundEnabled()) this.sound.play(this.modeValue)
    // Played once: the snapshot Turbo caches for Back now rests instead
    this.playValue = false
  }

  disconnect() {
    this.scene?.destroy()
    this.sound?.close()
  }

  replay() {
    this.scene.replay()
    if (soundEnabled()) this.sound.play(this.modeValue)
  }

  toggleSound() {
    const on = !soundEnabled()
    setSoundEnabled(on)
    if (!on) this.sound.stop()
    this.renderSoundToggle()
  }

  renderSoundToggle() {
    if (!this.hasSoundToggleTarget) return
    const on = soundEnabled()
    this.soundToggleTarget.setAttribute("aria-pressed", String(on))
    this.soundToggleTarget.title = on ? "Sound on" : "Sound off"
    this.soundToggleTarget.classList.toggle("sky__button--off", !on)
  }
}
