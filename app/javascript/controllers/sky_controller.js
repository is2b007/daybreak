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
  }

  disconnect() {
    this.scene?.destroy()
    this.sound?.stop()
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
