// The sky behind sunrise and sundown: a sun that rises (or sets) between the
// logo's two amber hills, with stars, drifting motes and a slow ambient loop.
//
// `elevation` drives everything: 0 is night, ~0.35 dawn/dusk, 1 full day.
// Sunrise animates 0 → SUNRISE_REST; sundown animates SUNDOWN_START → 0.
// Plain canvas, no dependencies, so the same file runs in the app and in previews.

const SUNRISE_REST = 0.86
const SUNDOWN_START = 0.62
const TRANSITION_MS = 7000

// [elevation, sky top, sky at horizon] — sRGB so stops interpolate predictably
const SKY = [
  [0.00, [10, 14, 34], [26, 30, 58]],
  [0.18, [24, 30, 66], [92, 64, 104]],
  [0.36, [62, 92, 150], [240, 150, 92]],
  [0.60, [120, 178, 228], [255, 206, 150]],
  [1.00, [176, 220, 248], [255, 240, 214]]
]

const HILL_BACK  = [[255, 196, 120], [232, 132, 40]]   // lit gradient, top → bottom
const HILL_FRONT = [[255, 170, 70], [214, 100, 18]]
const HILL_NIGHT = [46, 42, 74]

const lerp = (a, b, t) => a + (b - a) * t
const clamp01 = (t) => Math.min(1, Math.max(0, t))
const mix = (a, b, t) => a.map((v, i) => Math.round(lerp(v, b[i], t)))
const rgb = (c, a = 1) => `rgba(${c[0]}, ${c[1]}, ${c[2]}, ${a})`
const easeInOut = (t) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2)

function skyAt(e) {
  for (let i = 1; i < SKY.length; i++) {
    const [e1, top1, hor1] = SKY[i]
    const [e0, top0, hor0] = SKY[i - 1]
    if (e <= e1) {
      const t = (e - e0) / (e1 - e0)
      return [mix(top0, top1, t), mix(hor0, hor1, t)]
    }
  }
  return [SKY.at(-1)[1], SKY.at(-1)[2]]
}

// Small seeded PRNG so stars sit in the same places on every frame and resize
function seeded(seed) {
  let s = seed >>> 0
  return () => ((s = (s * 1664525 + 1013904223) >>> 0) / 4294967296)
}

export class SkyScene {
  constructor(canvas, { mode = "sunrise", play = true, reducedMotion = false } = {}) {
    this.canvas = canvas
    this.ctx = canvas.getContext("2d")
    this.mode = mode
    this.reducedMotion = reducedMotion
    this.from = mode === "sunrise" ? 0 : SUNDOWN_START
    this.to = mode === "sunrise" ? SUNRISE_REST : 0
    this.startedAt = null
    this.play = play && !reducedMotion
    this.frame = this.frame.bind(this)
    this.onVisibility = () => (document.hidden ? this.pause() : this.resume())

    const rand = seeded(mode === "sunrise" ? 7 : 11)
    this.stars = Array.from({ length: 140 }, () => ({
      x: rand(), y: rand() * 0.8, r: 0.4 + rand() * 1.2, phase: rand() * Math.PI * 2, speed: 0.6 + rand() * 1.6
    }))
    this.motes = Array.from({ length: 36 }, () => ({
      x: rand(), y: rand(), r: 0.6 + rand() * 1.8, drift: 0.004 + rand() * 0.012, sway: rand() * Math.PI * 2
    }))
    this.clouds = Array.from({ length: 4 }, (_, i) => ({
      x: rand(), y: 0.14 + i * 0.09 + rand() * 0.05, w: 0.18 + rand() * 0.2, speed: 0.0025 + rand() * 0.003
    }))
    this.shootingStar = null

    this.resizeObserver = new ResizeObserver(() => this.resize())
    this.resizeObserver.observe(canvas)
    this.resize()
  }

  start() {
    document.addEventListener("visibilitychange", this.onVisibility)
    if (this.reducedMotion) {
      this.draw(this.to, 0)
      return
    }
    this.resume()
  }

  pause() {
    cancelAnimationFrame(this.raf)
    this.raf = null
    this.pausedAt = performance.now()
  }

  resume() {
    if (this.raf) return
    if (this.pausedAt && this.startedAt) this.startedAt += performance.now() - this.pausedAt
    this.pausedAt = null
    this.raf = requestAnimationFrame(this.frame)
  }

  destroy() {
    cancelAnimationFrame(this.raf)
    this.resizeObserver.disconnect()
    document.removeEventListener("visibilitychange", this.onVisibility)
  }

  resize() {
    const dpr = Math.min(window.devicePixelRatio || 1, 2)
    const { width, height } = this.canvas.getBoundingClientRect()
    if (!width || !height) return
    this.w = width
    this.h = height
    this.canvas.width = Math.round(width * dpr)
    this.canvas.height = Math.round(height * dpr)
    this.ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
    if (!this.raf) this.draw(this.currentElevation ?? (this.play ? this.from : this.to), (this.lastTime ?? 0))
  }

  frame(now) {
    this.startedAt ??= now
    const elapsed = now - this.startedAt
    const progress = this.play ? clamp01(elapsed / TRANSITION_MS) : 1
    // Once the sky has settled, the ambient loop only needs ~30fps
    if (progress < 1 || now - (this.drawnAt ?? 0) > 32) {
      this.drawnAt = now
      this.draw(lerp(this.from, this.to, easeInOut(progress)), now / 1000)
    }
    this.raf = requestAnimationFrame(this.frame)
  }

  // Replays the transition from the top (used by previews and the replay control)
  replay() {
    this.play = !this.reducedMotion
    this.startedAt = null
    this.resume()
  }

  draw(e, time) {
    const { ctx, w, h } = this
    if (!w) return
    this.currentElevation = e
    this.lastTime = time
    // Hills keep a landscape proportion, so a tall immersive sky gets more sky, not taller hills
    const hillH = Math.min(h, w * 0.3)
    const horizon = h - hillH * 0.22
    const night = clamp01(1 - e / 0.4)

    // Sky
    const [top, hor] = skyAt(e)
    const sky = ctx.createLinearGradient(0, 0, 0, horizon)
    sky.addColorStop(0, rgb(top))
    sky.addColorStop(1, rgb(hor))
    ctx.fillStyle = sky
    ctx.fillRect(0, 0, w, h)

    // Stars fade in as the sky darkens, twinkling at their own pace
    if (night > 0.02) {
      for (const s of this.stars) {
        const twinkle = 0.55 + 0.45 * Math.sin(time * s.speed + s.phase)
        ctx.fillStyle = `rgba(255, 248, 230, ${night * twinkle * 0.9})`
        ctx.beginPath()
        ctx.arc(s.x * w, s.y * horizon, s.r, 0, Math.PI * 2)
        ctx.fill()
      }
      this.drawShootingStar(time, night)
    }

    // Sun: rises from behind the hills along a shallow arc
    const sunR = Math.max(26, Math.min(w, h) * 0.11)
    const sunX = w * 0.5 + (e - 0.5) * w * 0.06
    const sunY = horizon + sunR * 1.4 - e * (horizon * 0.62)
    const glowR = sunR * (4.2 + 0.25 * Math.sin(time * 0.8))
    const glow = ctx.createRadialGradient(sunX, sunY, sunR * 0.4, sunX, sunY, glowR)
    glow.addColorStop(0, `rgba(255, 214, 140, ${0.55 * clamp01(e * 1.6)})`)
    glow.addColorStop(1, "rgba(255, 214, 140, 0)")
    ctx.fillStyle = glow
    ctx.fillRect(0, 0, w, h)

    const disk = ctx.createRadialGradient(sunX - sunR * 0.3, sunY - sunR * 0.35, sunR * 0.1, sunX, sunY, sunR)
    disk.addColorStop(0, "rgb(255, 250, 225)")
    disk.addColorStop(0.45, "rgb(255, 222, 128)")
    disk.addColorStop(1, rgb(mix([255, 188, 70], [242, 110, 40], 1 - clamp01(e * 1.5))))
    ctx.fillStyle = disk
    ctx.beginPath()
    ctx.arc(sunX, sunY, sunR, 0, Math.PI * 2)
    ctx.fill()

    // Light rays through the dawn haze
    if (e > 0.25) {
      ctx.save()
      ctx.globalCompositeOperation = "lighter"
      const rays = 9
      for (let i = 0; i < rays; i++) {
        const a = -Math.PI / 2 + (i - (rays - 1) / 2) * 0.22 + Math.sin(time * 0.15 + i) * 0.03
        const len = h * 1.1
        const ray = ctx.createLinearGradient(sunX, sunY, sunX + Math.cos(a) * len, sunY + Math.sin(a) * len)
        ray.addColorStop(0, `rgba(255, 220, 160, ${0.035 * clamp01((e - 0.25) * 3)})`)
        ray.addColorStop(1, "rgba(255, 220, 160, 0)")
        ctx.fillStyle = ray
        ctx.beginPath()
        ctx.moveTo(sunX, sunY)
        ctx.lineTo(sunX + Math.cos(a - 0.05) * len, sunY + Math.sin(a - 0.05) * len)
        ctx.lineTo(sunX + Math.cos(a + 0.05) * len, sunY + Math.sin(a + 0.05) * len)
        ctx.closePath()
        ctx.fill()
      }
      ctx.restore()
    }

    // Soft cloud wisps drifting across, tinted by the light
    for (const c of this.clouds) {
      const x = ((c.x + time * c.speed) % 1.4) - 0.2
      const tint = mix([255, 236, 220], [120, 110, 160], night)
      const cloud = ctx.createRadialGradient(x * w, c.y * h, 0, x * w, c.y * h, c.w * w)
      cloud.addColorStop(0, rgb(tint, 0.28 - night * 0.12))
      cloud.addColorStop(1, rgb(tint, 0))
      ctx.save()
      ctx.translate(x * w, c.y * h)
      ctx.scale(1, 0.22)
      ctx.translate(-x * w, -c.y * h)
      ctx.fillStyle = cloud
      ctx.fillRect(x * w - c.w * w, c.y * h - c.w * w, c.w * w * 2, c.w * w * 2)
      ctx.restore()
    }

    // The logo's twin hills: back hill left, front hill right, lit by the sun
    const light = clamp01(e * 1.4)
    this.drawHill(w * -0.1, w * 0.64, horizon - hillH * 0.2, h, HILL_BACK, light, 0.92)
    this.drawHill(w * 0.36, w * 1.12, horizon - hillH * 0.1, h, HILL_FRONT, light, 1)

    // Motes of light drift up in the morning; fireflies blink low at dusk
    for (const m of this.motes) {
      const rise = this.mode === "sunrise"
      const y = rise ? (1 - ((m.y + time * m.drift) % 1)) : (0.62 + ((m.y * 0.35 + Math.sin(time * 0.4 + m.sway) * 0.03)))
      const x = m.x + Math.sin(time * 0.5 + m.sway) * 0.01
      const a = rise
        ? 0.5 * clamp01(e * 1.5) * Math.sin(Math.PI * y)
        : night * Math.max(0, Math.sin(time * 1.3 + m.sway * 3)) * 0.9
      if (a <= 0.01) continue
      ctx.fillStyle = rise ? `rgba(255, 240, 200, ${a})` : `rgba(255, 226, 120, ${a})`
      ctx.beginPath()
      ctx.arc(x * w, y * h, m.r, 0, Math.PI * 2)
      ctx.fill()
    }
  }

  drawHill(x0, x1, peakY, h, [lit0, lit1], light, scale) {
    const { ctx } = this
    const top = mix(HILL_NIGHT, lit0, light)
    const bottom = mix(HILL_NIGHT, lit1, light * 0.9)
    const g = ctx.createLinearGradient(0, peakY, 0, h)
    g.addColorStop(0, rgb(top))
    g.addColorStop(1, rgb(bottom))
    ctx.fillStyle = g
    const mid = (x0 + x1) / 2
    ctx.beginPath()
    ctx.moveTo(x0, h)
    ctx.bezierCurveTo(x0 + (mid - x0) * 0.45, peakY - h * 0.02 * scale, mid - (x1 - x0) * 0.24, peakY, mid, peakY)
    ctx.bezierCurveTo(mid + (x1 - x0) * 0.24, peakY, x1 - (x1 - mid) * 0.45, peakY + h * 0.02, x1, h)
    ctx.closePath()
    ctx.fill()

    // Glossy rim, as on the logo; a cool moonlit edge once the sun is gone
    ctx.save()
    ctx.clip()
    const sheen = ctx.createLinearGradient(0, peakY, 0, peakY + h * 0.08)
    const rim = mix([170, 180, 235], [255, 255, 255], light)
    sheen.addColorStop(0, rgb(rim, 0.28 * light + 0.22 * (1 - light)))
    sheen.addColorStop(1, rgb(rim, 0))
    ctx.fillStyle = sheen
    ctx.fillRect(x0, peakY, x1 - x0, h * 0.08)
    ctx.restore()
  }

  drawShootingStar(time, night) {
    if (this.mode !== "sundown" || night < 0.7) return
    const { ctx, w, h } = this
    if (!this.shootingStar && Math.random() < 0.004) {
      this.shootingStar = { x: 0.2 + Math.random() * 0.6, y: 0.08 + Math.random() * 0.2, born: time }
    }
    const s = this.shootingStar
    if (!s) return
    const t = (time - s.born) / 0.9
    if (t > 1) { this.shootingStar = null; return }
    const x = (s.x + t * 0.18) * w
    const y = (s.y + t * 0.08) * h
    const tail = ctx.createLinearGradient(x, y, x - w * 0.08, y - h * 0.035)
    tail.addColorStop(0, `rgba(255, 250, 235, ${0.9 * (1 - t)})`)
    tail.addColorStop(1, "rgba(255, 250, 235, 0)")
    ctx.strokeStyle = tail
    ctx.lineWidth = 1.4
    ctx.beginPath()
    ctx.moveTo(x, y)
    ctx.lineTo(x - w * 0.08, y - h * 0.035)
    ctx.stroke()
  }
}
