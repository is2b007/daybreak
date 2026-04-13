export const SNAP_MINUTES = 15
export const MIN_DURATION_MINUTES = 15

/** Snap “minutes since local midnight” to the timeline grid (15 min). */
export function snapMinutesFromMidnight(totalMin) {
  return Math.round(totalMin / SNAP_MINUTES) * SNAP_MINUTES
}

export function snapDurationMinutes(mins) {
  return Math.max(MIN_DURATION_MINUTES, Math.round(mins / SNAP_MINUTES) * SNAP_MINUTES)
}

/** Local calendar date + minutes from midnight → Date (browser local). */
export function wallFromMinutesSinceMidnight(y, month, d, mins) {
  const midnight = new Date(y, month - 1, d, 0, 0, 0)
  return new Date(midnight.getTime() + mins * 60000)
}
