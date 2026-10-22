import { Controller } from "@hotwired/stimulus"

const KEY = "daybreak:focusSound"
const MOODS = ["off", "rain", "waves", "drift"]

// Calm background sound for Focus, generated with Web Audio so there are no
// files to load or license. Nothing plays until the person picks a mood
// (browsers block audio without a gesture); the choice is remembered and
// offered again next time, but never auto-started.
export default class extends Controller {
  static targets = ["option"]

  connect() {
    let stored = null
    try { stored = localStorage.getItem(KEY) } catch (_) { /* private mode */ }
    this.remembered = MOODS.includes(stored) ? stored : "off"
    this.#mark("off")
    this.#hint(this.remembered)
  }

  disconnect() {
    this.#stop(0.4)
    // Browsers cap open AudioContexts; each Focus visit makes a new controller
    const ctx = this.ctx
    this.ctx = null
    if (ctx) setTimeout(() => ctx.close().catch(() => {}), 700)
  }

  pick(event) {
    const mood = event.currentTarget.dataset.mood
    try { localStorage.setItem(KEY, mood) } catch (_) { /* private mode */ }
    this.#stop(1.2)
    this.#mark(mood)
    if (mood !== "off") this.#start(mood)
  }

  #mark(mood) {
    this.optionTargets.forEach(o => {
      const on = o.dataset.mood === mood
      o.classList.toggle("on", on)
      o.setAttribute("aria-pressed", String(on))
    })
  }

  #hint(mood) {
    this.optionTargets.forEach(o => o.classList.toggle("last", mood !== "off" && o.dataset.mood === mood))
  }

  #start(mood) {
    const ctx = this.ctx ||= new (window.AudioContext || window.webkitAudioContext)()
    ctx.resume()
    const out = ctx.createGain()
    out.gain.value = 0
    out.gain.setTargetAtTime(1, ctx.currentTime, 1.2)
    out.connect(ctx.destination)
    this.out = out
    this.timers = []
    this.nodes = []
    if (mood === "rain") this.#rain(ctx, out)
    if (mood === "waves") this.#waves(ctx, out)
    if (mood === "drift") this.#drift(ctx, out)
  }

  #stop(fade) {
    if (!this.out || !this.ctx) return
    const { out, nodes, timers, ctx } = this
    timers.forEach(clearInterval)
    out.gain.cancelScheduledValues(ctx.currentTime)
    out.gain.setTargetAtTime(0, ctx.currentTime, fade / 3)
    setTimeout(() => { nodes.forEach(n => { try { n.stop() } catch (_) {} }); out.disconnect() }, fade * 1000 + 200)
    this.out = null
  }

  // Brown noise: soft and low, the basis for rain and surf.
  #noise(ctx) {
    const len = ctx.sampleRate * 4
    const buf = ctx.createBuffer(2, len, ctx.sampleRate)
    for (let ch = 0; ch < 2; ch++) {
      const d = buf.getChannelData(ch)
      let last = 0
      for (let i = 0; i < len; i++) {
        last = (last + 0.02 * (Math.random() * 2 - 1)) / 1.02
        d[i] = last * 3.5
      }
    }
    const src = ctx.createBufferSource()
    src.buffer = buf
    src.loop = true
    src.start()
    this.nodes.push(src)
    return src
  }

  #rain(ctx, out) {
    const src = this.#noise(ctx)
    const hp = new BiquadFilterNode(ctx, { type: "highpass", frequency: 400 })
    const lp = new BiquadFilterNode(ctx, { type: "lowpass", frequency: 2600 })
    const g = new GainNode(ctx, { gain: 0.5 })
    src.connect(hp).connect(lp).connect(g).connect(out)
    // A low rumble underneath so it reads as rain on a roof, not static.
    const body = this.#noise(ctx)
    const blp = new BiquadFilterNode(ctx, { type: "lowpass", frequency: 300 })
    body.connect(blp).connect(new GainNode(ctx, { gain: 0.6 })).connect(out)
  }

  #waves(ctx, out) {
    const src = this.#noise(ctx)
    const lp = new BiquadFilterNode(ctx, { type: "lowpass", frequency: 700 })
    const swell = new GainNode(ctx, { gain: 0.25 })
    src.connect(lp).connect(swell).connect(out)
    // Each wave: a slow rise and a longer fall, about ten seconds apart.
    const wave = () => {
      const t = ctx.currentTime
      const peak = 0.55 + Math.random() * 0.3
      swell.gain.cancelScheduledValues(t)
      swell.gain.setTargetAtTime(peak, t, 1.6)
      swell.gain.setTargetAtTime(0.12, t + 3.5, 2.4)
      lp.frequency.setTargetAtTime(1100, t, 1.6)
      lp.frequency.setTargetAtTime(500, t + 3.5, 2.4)
    }
    wave()
    this.timers.push(setInterval(wave, 9500))
  }

  #drift(ctx, out) {
    // Slow ambient pad: a few detuned voices gliding between four warm chords.
    const chords = [
      [110.0, 164.81, 220.0, 277.18, 329.63],
      [92.5, 138.59, 185.0, 220.0, 277.18],
      [73.42, 146.83, 220.0, 277.18, 369.99],
      [82.41, 123.47, 164.81, 246.94, 311.13]
    ]
    const lp = new BiquadFilterNode(ctx, { type: "lowpass", frequency: 900, Q: 0.4 })
    const g = new GainNode(ctx, { gain: 0.07 })
    lp.connect(g).connect(out)
    const lfo = new OscillatorNode(ctx, { frequency: 0.05 })
    const depth = new GainNode(ctx, { gain: 350 })
    lfo.connect(depth).connect(lp.frequency)
    lfo.start()
    this.nodes.push(lfo)
    const voices = chords[0].map((f, i) => {
      const o = new OscillatorNode(ctx, { type: i % 2 ? "sine" : "triangle", frequency: f, detune: (i - 2) * 4 })
      o.connect(lp)
      o.start()
      this.nodes.push(o)
      return o
    })
    let n = 0
    this.timers.push(setInterval(() => {
      n = (n + 1) % chords.length
      voices.forEach((o, i) => o.frequency.setTargetAtTime(chords[n][i], ctx.currentTime, 2.5))
    }, 14000))
  }
}
