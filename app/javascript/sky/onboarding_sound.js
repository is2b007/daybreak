// The sound of onboarding, generated with Web Audio like the ritual cues:
// a slow pad with a little air under it that moves to a new chord on each
// step, a bell as each step arrives, soft plucks while typing, a stamp thud,
// and a rising run of bells when the sun comes up.
//
// Audio can only start after the person interacts with the page, so the
// controller calls start() from the first click or key press.

import { hz, makeReverb } from "sky/sound"

// One chord per step, drifting around C major and landing on the same
// C major 9 the sunrise ritual uses
const CHORDS = [
  [41, 48, 57, 64, 67],     // Fmaj9, night
  [45, 52, 60, 67, 71],     // Am9
  [48, 55, 64, 71, 74],     // Cmaj9, the sun comes up
  [41, 53, 57, 64, 69],     // Fmaj7 add 6
  [43, 50, 57, 62, 66],     // G6/9 with a lifted 3rd
  [45, 52, 59, 64, 67],     // Am11
  [48, 55, 64, 69, 74, 79]  // C6/9, morning
]

// C major pentatonic, two octaves up from middle C
const BELLS = [72, 74, 76, 79, 81, 84, 86, 88, 91]

const PAD_LEVEL = 0.05
const AIR_LEVEL = 0.012

export class OnboardingSound {
  constructor() {
    this.ctx = null
    this.chord = null
    this.lastTick = 0
  }

  get running() {
    return this.ctx?.state === "running" && !!this.master
  }

  async start(step = 1, { volume = 0.9 } = {}) {
    try {
      const ctx = (this.ctx ??= new (window.AudioContext || window.webkitAudioContext)())
      if (ctx.state === "suspended") await ctx.resume()
      if (ctx.state !== "running") return false
      if (this.master) return true

      const now = ctx.currentTime
      this.volume = volume
      this.master = ctx.createGain()
      this.master.gain.setValueAtTime(0, now)
      this.master.gain.linearRampToValueAtTime(volume, now + 2.5)
      this.master.connect(ctx.destination)

      this.reverb = makeReverb(ctx, 4)
      const wet = ctx.createGain()
      wet.gain.value = 0.5
      this.reverb.connect(wet).connect(this.master)

      this.air(ctx)
      this.setStep(step, { fade: 3 })
      return true
    } catch {
      return false
    }
  }

  stop(fade = 0.6) {
    if (!this.master || !this.ctx) return
    const g = this.master.gain
    const t = this.ctx.currentTime
    g.cancelScheduledValues(t)
    g.setValueAtTime(g.value, t)
    g.linearRampToValueAtTime(0, t + fade)
    const old = this.master
    const sources = [this.airSource, this.airLfo, ...(this.chord?.oscs ?? [])]
    setTimeout(() => {
      sources.forEach((s) => { try { s?.stop() } catch {} })
      old.disconnect()
    }, fade * 1000 + 200)
    this.master = null
    this.chord = null
    this.airSource = null
    this.airLfo = null
  }

  // Releases the AudioContext; browsers cap how many can be open at once
  close(fade = 0.6) {
    this.stop(fade)
    const ctx = this.ctx
    this.ctx = null
    if (ctx) setTimeout(() => ctx.close().catch(() => {}), fade * 1000 + 300)
  }

  // Turns the whole thing down to a murmur while nobody's there, and back up
  settle(quiet) {
    if (!this.master) return
    const g = this.master.gain
    const t = this.ctx.currentTime
    g.cancelScheduledValues(t)
    g.setValueAtTime(g.value, t)
    g.linearRampToValueAtTime(quiet ? this.volume * 0.3 : this.volume, t + (quiet ? 8 : 1.5))
  }

  // Crossfades the pad to the chord for this step
  setStep(step, { fade = 3.5 } = {}) {
    if (!this.master) return
    const ctx = this.ctx
    const notes = CHORDS[Math.min(Math.max(step, 1), CHORDS.length) - 1]
    const now = ctx.currentTime

    if (this.chord) {
      const old = this.chord
      old.gain.gain.cancelScheduledValues(now)
      old.gain.gain.setValueAtTime(old.gain.gain.value, now)
      old.gain.gain.linearRampToValueAtTime(0, now + fade)
      old.oscs.forEach((o) => o.stop(now + fade + 0.1))
    }

    const gain = ctx.createGain()
    gain.gain.setValueAtTime(0, now)
    gain.gain.linearRampToValueAtTime(PAD_LEVEL, now + fade)

    // A lowpass that slowly breathes open and closed
    const filter = ctx.createBiquadFilter()
    filter.type = "lowpass"
    filter.frequency.value = 700 + step * 90
    filter.Q.value = 0.6
    const lfo = ctx.createOscillator()
    lfo.frequency.value = 0.07
    const depth = ctx.createGain()
    depth.gain.value = 260
    lfo.connect(depth).connect(filter.frequency)

    filter.connect(gain)
    gain.connect(this.master)
    gain.connect(this.reverb)

    const oscs = [lfo]
    for (const note of notes) {
      for (const [type, detune] of [["triangle", -5], ["sine", 6]]) {
        const osc = ctx.createOscillator()
        osc.type = type
        osc.frequency.value = hz(note)
        osc.detune.value = detune
        const voice = ctx.createGain()
        voice.gain.value = 1 / notes.length
        osc.connect(voice).connect(filter)
        oscs.push(osc)
      }
    }
    oscs.forEach((o) => o.start(now))
    this.chord = { gain, oscs }
  }

  // A single struck bell; higher steps ring a little higher
  chime(step = 1, { delay = 0, level = 0.09 } = {}) {
    if (!this.running) return
    const note = BELLS[Math.min(step - 1, BELLS.length - 1)]
    this.bell(note, this.ctx.currentTime + delay, level)
  }

  // The sun coming up: a slow rising run of bells
  flourish({ delay = 0 } = {}) {
    if (!this.running) return
    const start = this.ctx.currentTime + delay
    BELLS.slice(2).forEach((note, i) => this.bell(note, start + i * 0.32 + (i % 2) * 0.05, 0.07))
  }

  // A soft pluck for each key pressed while typing, never more than ~12 a second
  tick() {
    if (!this.running) return
    const now = this.ctx.currentTime
    if (now - this.lastTick < 0.08) return
    this.lastTick = now
    const note = BELLS[Math.floor(Math.random() * 5) + 2]
    const osc = this.ctx.createOscillator()
    osc.type = "triangle"
    osc.frequency.value = hz(note)
    const env = this.ctx.createGain()
    env.gain.setValueAtTime(0, now)
    env.gain.linearRampToValueAtTime(0.022, now + 0.006)
    env.gain.exponentialRampToValueAtTime(0.0001, now + 0.35)
    osc.connect(env)
    env.connect(this.master)
    env.connect(this.reverb)
    osc.start(now)
    osc.stop(now + 0.4)
  }

  // A rubber stamp landing on paper: a low thud with a papery tap on top
  stamp() {
    if (!this.running) return
    const ctx = this.ctx
    const now = ctx.currentTime

    const thud = ctx.createOscillator()
    thud.type = "sine"
    thud.frequency.setValueAtTime(150, now)
    thud.frequency.exponentialRampToValueAtTime(52, now + 0.14)
    const thudEnv = ctx.createGain()
    thudEnv.gain.setValueAtTime(0, now)
    thudEnv.gain.linearRampToValueAtTime(0.32, now + 0.005)
    thudEnv.gain.exponentialRampToValueAtTime(0.0001, now + 0.32)
    thud.connect(thudEnv).connect(this.master)
    thud.start(now)
    thud.stop(now + 0.35)

    const tap = ctx.createBufferSource()
    tap.buffer = this.noise(0.08)
    const tapFilter = ctx.createBiquadFilter()
    tapFilter.type = "lowpass"
    tapFilter.frequency.value = 1400
    const tapEnv = ctx.createGain()
    tapEnv.gain.setValueAtTime(0.12, now)
    tapEnv.gain.exponentialRampToValueAtTime(0.0001, now + 0.07)
    tap.connect(tapFilter).connect(tapEnv).connect(this.master)
    tap.start(now)
  }

  bell(note, t, level) {
    const ctx = this.ctx
    // A sine with quieter inharmonic partials, struck and left to ring
    for (const [ratio, partial] of [[1, 1], [2.76, 0.3], [5.4, 0.1]]) {
      const osc = ctx.createOscillator()
      osc.type = "sine"
      osc.frequency.value = hz(note) * ratio
      const env = ctx.createGain()
      env.gain.setValueAtTime(0, t)
      env.gain.linearRampToValueAtTime(level * partial, t + 0.01)
      env.gain.exponentialRampToValueAtTime(0.0001, t + 3 / ratio + 0.5)
      osc.connect(env)
      env.connect(this.master)
      env.connect(this.reverb)
      osc.start(t)
      osc.stop(t + 3.6)
    }
  }

  // Filtered noise that swells and settles like a breeze
  air(ctx) {
    const src = ctx.createBufferSource()
    src.buffer = this.noise(4)
    src.loop = true
    const band = ctx.createBiquadFilter()
    band.type = "bandpass"
    band.frequency.value = 520
    band.Q.value = 0.4
    const gain = ctx.createGain()
    gain.gain.value = AIR_LEVEL
    const lfo = ctx.createOscillator()
    lfo.frequency.value = 0.045
    const depth = ctx.createGain()
    depth.gain.value = AIR_LEVEL * 0.8
    lfo.connect(depth).connect(gain.gain)
    src.connect(band).connect(gain).connect(this.master)
    src.start()
    lfo.start()
    this.airSource = src
    this.airLfo = lfo
  }

  noise(seconds) {
    const length = Math.floor(this.ctx.sampleRate * seconds)
    const buffer = this.ctx.createBuffer(1, length, this.ctx.sampleRate)
    const data = buffer.getChannelData(0)
    for (let i = 0; i < length; i++) data[i] = Math.random() * 2 - 1
    return buffer
  }
}
