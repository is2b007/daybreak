// Generative ritual sounds, made with Web Audio rather than shipped as files:
// a warm pad that opens up as the sun rises (or closes as it sets), a few
// soft bells, and crickets once the sky is dark. ~10 seconds, then silence.
//
// Browsers only allow audio after the person has interacted with the page;
// rituals are reached by a click, so playback normally starts. If it is
// blocked, the replay control starts it from a click instead.

const STORAGE_KEY = "daybreak.sound"

export function soundEnabled() {
  try {
    return localStorage.getItem(STORAGE_KEY) !== "off"
  } catch {
    return true
  }
}

export function setSoundEnabled(on) {
  try {
    localStorage.setItem(STORAGE_KEY, on ? "on" : "off")
  } catch {
    // Storage blocked: the toggle still works for this page
  }
}

export const hz = (midi) => 440 * Math.pow(2, (midi - 69) / 12)

const CUES = {
  // C major 9, opening upward
  sunrise: {
    pad: [48, 55, 64, 71, 74],
    bells: [72, 76, 79, 81, 84, 88],
    filterFrom: 300, filterTo: 2600,
    crickets: false
  },
  // A minor 9, settling downward
  sundown: {
    pad: [45, 52, 55, 60, 71],
    bells: [88, 84, 81, 79, 76, 72],
    filterFrom: 2200, filterTo: 380,
    crickets: true
  }
}

export class RitualSound {
  constructor() {
    this.ctx = null
    this.master = null
  }

  async play(name, { volume = 0.32 } = {}) {
    const cue = CUES[name]
    if (!cue) return false
    try {
      this.stop()
      const ctx = (this.ctx ??= new (window.AudioContext || window.webkitAudioContext)())
      if (ctx.state === "suspended") await ctx.resume()
      if (ctx.state !== "running") return false

      const now = ctx.currentTime + 0.05
      const master = (this.master = ctx.createGain())
      master.gain.setValueAtTime(0, now)
      master.gain.linearRampToValueAtTime(volume, now + 1.5)
      master.gain.setValueAtTime(volume, now + 8)
      master.gain.linearRampToValueAtTime(0, now + 12)
      master.connect(ctx.destination)

      const reverb = this.reverb(ctx)
      const wet = ctx.createGain()
      wet.gain.value = 0.45
      reverb.connect(wet).connect(master)

      this.pad(ctx, cue, now, master, reverb)
      this.bells(ctx, cue, now, master, reverb)
      if (cue.crickets) this.crickets(ctx, now + 4.5, master)
      return true
    } catch {
      return false
    }
  }

  stop() {
    if (!this.master || !this.ctx) return
    const g = this.master.gain
    const t = this.ctx.currentTime
    g.cancelScheduledValues(t)
    g.setValueAtTime(g.value, t)
    g.linearRampToValueAtTime(0, t + 0.4)
    const old = this.master
    setTimeout(() => old.disconnect(), 600)
    this.master = null
  }

  pad(ctx, cue, now, out, reverb) {
    const filter = ctx.createBiquadFilter()
    filter.type = "lowpass"
    filter.Q.value = 0.7
    filter.frequency.setValueAtTime(cue.filterFrom, now)
    filter.frequency.exponentialRampToValueAtTime(cue.filterTo, now + 7)
    const gain = ctx.createGain()
    gain.gain.setValueAtTime(0, now)
    gain.gain.linearRampToValueAtTime(0.16, now + 2.8)
    gain.gain.setValueAtTime(0.16, now + 7.5)
    gain.gain.linearRampToValueAtTime(0, now + 11.5)
    filter.connect(gain)
    gain.connect(out)
    gain.connect(reverb)

    for (const note of cue.pad) {
      for (const detune of [-7, 7]) {
        const osc = ctx.createOscillator()
        osc.type = "sawtooth"
        osc.frequency.value = hz(note)
        osc.detune.value = detune
        const voice = ctx.createGain()
        voice.gain.value = 0.5 / cue.pad.length
        osc.connect(voice).connect(filter)
        osc.start(now)
        osc.stop(now + 12)
      }
    }
  }

  bells(ctx, cue, now, out, reverb) {
    cue.bells.forEach((note, i) => {
      const t = now + 1.4 + i * 0.62 + (i % 2) * 0.08
      // A bell is a sine with a quieter inharmonic partial, struck and left to ring
      for (const [ratio, level] of [[1, 0.11], [2.76, 0.035], [5.4, 0.012]]) {
        const osc = ctx.createOscillator()
        osc.type = "sine"
        osc.frequency.value = hz(note) * ratio
        const env = ctx.createGain()
        env.gain.setValueAtTime(0, t)
        env.gain.linearRampToValueAtTime(level, t + 0.008)
        env.gain.exponentialRampToValueAtTime(0.0001, t + 2.6 / ratio + 0.4)
        osc.connect(env)
        env.connect(out)
        env.connect(reverb)
        osc.start(t)
        osc.stop(t + 3.2)
      }
    })
  }

  crickets(ctx, start, out) {
    // A high tone gated in quick triplets, twice a second, very quietly
    const osc = ctx.createOscillator()
    osc.type = "sine"
    osc.frequency.value = 4400
    const gate = ctx.createGain()
    gate.gain.value = 0
    const level = ctx.createGain()
    level.gain.setValueAtTime(0, start)
    level.gain.linearRampToValueAtTime(0.018, start + 2)
    osc.connect(gate).connect(level).connect(out)
    for (let t = start; t < start + 7.5; t += 0.5 + Math.random() * 0.15) {
      for (let k = 0; k < 3; k++) {
        const p = t + k * 0.045
        gate.gain.setValueAtTime(0, p)
        gate.gain.linearRampToValueAtTime(1, p + 0.008)
        gate.gain.linearRampToValueAtTime(0, p + 0.03)
      }
    }
    osc.start(start)
    osc.stop(start + 8)
  }

  reverb(ctx) {
    return makeReverb(ctx)
  }
}

// A soft room: decaying noise as the impulse response, no sample files
export function makeReverb(ctx, seconds = 3) {
  const length = ctx.sampleRate * seconds
  const impulse = ctx.createBuffer(2, length, ctx.sampleRate)
  for (let ch = 0; ch < 2; ch++) {
    const data = impulse.getChannelData(ch)
    for (let i = 0; i < length; i++) data[i] = (Math.random() * 2 - 1) * Math.pow(1 - i / length, 2.4)
  }
  const conv = ctx.createConvolver()
  conv.buffer = impulse
  return conv
}
