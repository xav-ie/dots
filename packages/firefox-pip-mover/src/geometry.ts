// Pure geometry + animation math for the Firefox PiP mover.
//
// Everything here is a pure function of plain numbers (no Firefox/XPCOM/DOM
// access), so it can be unit-tested with simulated screen/window rects. The
// impure shell (main.ts) reads the live window geometry, calls these, and
// applies the result via nsIBaseWindow/moveTo.

export interface Rect {
  x: number;
  y: number;
  w: number;
  h: number;
}

export type HEdge = "left" | "middle" | "right";
export type VEdge = "top" | "middle" | "bottom";

export const MOVE_ANCHORS = [
  "top-left",
  "top-right",
  "bottom-right",
  "bottom-left",
  "top-middle",
  "middle-middle",
  "bottom-middle",
] as const;
export type MoveAnchor = (typeof MOVE_ANCHORS)[number];
export type Anchor = MoveAnchor | "grow" | "shrink";

const ALL_ANCHORS = new Set<string>([...MOVE_ANCHORS, "grow", "shrink"]);

export function isAnchor(s: string): s is Anchor {
  return ALL_ANCHORS.has(s);
}

export function isMoveAnchor(s: string): s is MoveAnchor {
  return (MOVE_ANCHORS as readonly string[]).includes(s);
}

// "Magnetized" anchor: which third of the screen the window's center sits in.
export function pickEdges(win: Rect, screen: Rect): { hx: HEdge; hy: VEdge } {
  const cx = win.x + win.w / 2;
  const cy = win.y + win.h / 2;
  const hx: HEdge =
    cx < screen.x + screen.w / 3
      ? "left"
      : cx > screen.x + (screen.w * 2) / 3
        ? "right"
        : "middle";
  const hy: VEdge =
    cy < screen.y + screen.h / 3
      ? "top"
      : cy > screen.y + (screen.h * 2) / 3
        ? "bottom"
        : "middle";
  return { hx, hy };
}

// Top-left position for a corner/edge snap; the window keeps its current size
// and is placed within the screen's available rect.
export function movePosition(
  anchor: MoveAnchor,
  win: Rect,
  screen: Rect,
): { x: number; y: number } {
  const left = screen.x;
  const right = screen.x + screen.w - win.w;
  const top = screen.y;
  const bottom = screen.y + screen.h - win.h;
  const cenX = screen.x + (screen.w - win.w) / 2;
  const cenY = screen.y + (screen.h - win.h) / 2;
  switch (anchor) {
    case "top-left":
      return { x: left, y: top };
    case "top-right":
      return { x: right, y: top };
    case "bottom-right":
      return { x: right, y: bottom };
    case "bottom-left":
      return { x: left, y: bottom };
    case "top-middle":
      return { x: cenX, y: top };
    case "middle-middle":
      return { x: cenX, y: cenY };
    case "bottom-middle":
      return { x: cenX, y: bottom };
  }
}

// Magnet for free dragging: given a free top-left (x,y), if it's within
// `threshold` of one of the snap anchors' positions, return that anchor's
// position; otherwise return (x,y) unchanged. Used so a two-finger drag moves
// the PiP freely but snaps when it gets near a corner/edge/center.
export function snapPosition(
  x: number,
  y: number,
  win: Rect,
  screen: Rect,
  threshold: number,
): { x: number; y: number } {
  let bx = x;
  let by = y;
  let bd = threshold;
  for (const a of MOVE_ANCHORS) {
    const p = movePosition(a, win, screen);
    const d = Math.hypot(p.x - x, p.y - y);
    if (d <= bd) {
      bd = d;
      bx = p.x;
      by = p.y;
    }
  }
  return { x: bx, y: by };
}

// Aspect-preserving clamp of a size into [minW, maxW] x (.., maxH].
export function clampSize(
  w: number,
  h: number,
  minW: number,
  maxW: number,
  maxH: number,
): { w: number; h: number } {
  const aspect = w / h;
  if (w < minW) {
    w = minW;
    h = w / aspect;
  }
  if (w > maxW || h > maxH) {
    const k = Math.min(maxW / w, maxH / h);
    w *= k;
    h *= k;
  }
  return { w, h };
}

/**
 * Snap a float size onto the display's pixel grid while holding a LOCKED aspect.
 *
 * Window sizes must be whole device pixels, and macOS's WindowServer further
 * snaps to whole points — so rounding width and height INDEPENDENTLY makes the
 * aspect (and thus the shape) shimmer by ~1px as the window grows/shrinks.
 * Instead, snap the driving dimension (the larger one) to the grid and DERIVE
 * the other from `aspect`, so the shape changes coherently and never re-snaps.
 *
 * `grid` is device-pixels-per-point (the dpr) so results land on whole points;
 * pass 1 when already working in points (the moveTo/resizeTo fallback).
 */
// `gridW`/`gridH` are per-axis snap quanta. For an EDGE-anchored axis pass the
// point grid (dpr); for a CENTER-anchored axis pass 2×grid (even points) so
// size/2 is always a whole point and the centered position can't wobble ±½pt as
// the window grows. The driving (larger) dimension is snapped and the other is
// derived from `aspect` then snapped, so the shape stays coherent.
export function quantizeSize(
  w: number,
  h: number,
  aspect: number,
  gridW: number,
  gridH: number,
): { w: number; h: number } {
  const gw = gridW > 0 ? gridW : 1;
  const gh = gridH > 0 ? gridH : 1;
  const snapW = (v: number) => Math.round(v / gw) * gw;
  const snapH = (v: number) => Math.round(v / gh) * gh;
  if (aspect >= 1) {
    const ww = snapW(w);
    return { w: ww, h: snapH(ww / aspect) };
  }
  const hh = snapH(h);
  return { w: snapW(hh * aspect), h: hh };
}

export interface AnchorEdges {
  left: number;
  right: number;
  top: number;
  bottom: number;
  midX: number;
  midY: number;
}

// Pixel-exact top-left for a given size, holding the magnetized edge/corner
// fixed: round the size first (caller's job), then derive the position from the
// frozen anchor edge so the pinned side never wobbles between frames.
export function anchoredPosition(
  hx: HEdge,
  hy: VEdge,
  e: AnchorEdges,
  w: number,
  h: number,
  grid: number,
): { x: number; y: number } {
  // Snap the position to the point grid so the WindowServer never re-snaps it to
  // a different whole point (which would shift the origin). With an even-point
  // size on a centered axis (see quantizeSize), this keeps the center exact.
  const g = grid > 0 ? grid : 1;
  const snap = (v: number) => Math.round(v / g) * g;
  const x =
    hx === "left"
      ? snap(e.left)
      : hx === "right"
        ? snap(e.right - w)
        : snap(e.midX - w / 2);
  const y =
    hy === "top"
      ? snap(e.top)
      : hy === "bottom"
        ? snap(e.bottom - h)
        : snap(e.midY - h / 2);
  return { x, y };
}

// Largest size that still fits the screen's available area WHEN GROWN ABOUT THIS
// ANCHOR. Without this, the size limit is the whole screen, so a centered (or
// off-center) window can try to grow past an edge; macOS then hard-clamps the
// window's top against the menu bar and the origin gets shoved off-center. By
// capping to what fits at the anchor, the window touches the edge and stops,
// staying put. `bounds` and `e` must be in the same units (device px).
export function anchorMaxSize(
  hx: HEdge,
  hy: VEdge,
  e: AnchorEdges,
  bounds: { left: number; top: number; right: number; bottom: number },
): { maxW: number; maxH: number } {
  const maxW =
    hx === "left"
      ? bounds.right - e.left
      : hx === "right"
        ? e.right - bounds.left
        : 2 * Math.min(e.midX - bounds.left, bounds.right - e.midX);
  const maxH =
    hy === "top"
      ? bounds.bottom - e.top
      : hy === "bottom"
        ? e.bottom - bounds.top
        : 2 * Math.min(e.midY - bounds.top, bounds.bottom - e.midY);
  return { maxW: Math.max(0, maxW), maxH: Math.max(0, maxH) };
}

// --- velocity-eased exponential scaling -------------------------------------

/** Clamp to [0,1]. */
export function clamp01(t: number): number {
  return t < 0 ? 0 : t > 1 ? 1 : t;
}

/**
 * Ken Perlin's smootherstep (6t^5 - 15t^4 + 10t^3): eases 0->1 with zero first
 * AND second derivative at both ends, so a ramp built on it has no perceptible
 * "kick" at onset or notch at the end.
 */
export function smootherstep(t: number): number {
  t = clamp01(t);
  return t * t * t * (t * (t * 6 - 15) + 10);
}

// Release behaviour, kept pure so the shell's branch is unit-testable:
// glide to a stop only after a genuinely fast sweep, else stop crisply.
export function shouldGlide(logVel: number, glideThreshold: number): boolean {
  return Math.abs(logVel) > glideThreshold;
}
// True once the glide has decayed enough to stop the loop.
export function atRest(logVel: number, restEps: number): boolean {
  return Math.abs(logVel) < restEps;
}

export interface ScaleState {
  logVel: number; // current velocity in log-size space (per second)
  heldSec: number; // how long the current direction has been held (drives accel)
  w: number;
  h: number;
}

export interface ScaleParams {
  minLogVel: number; // speed at the START of a hold = ln(minScalePerSec)
  maxLogVel: number; // speed cap after ramping = ln(maxScalePerSec)
  accelSec: number; // time to ramp from min->max while held (0 = instant max)
  tau: number; // per-frame velocity smoothing constant (s); 0 = instant
  minW: number;
  maxW: number;
  maxH: number;
}

// One animation frame. The target speed ACCELERATES the longer the key is held:
// it ramps (smootherstep) from minLogVel up to maxLogVel over accelSec — so a
// quick tap stays slow/precise and a sustained hold zooms fast. The per-frame
// velocity is then eased toward that target (tau) and applied to the size in
// LOG space (constant perceived zoom rate), aspect-preserving + clamped.
// dir: +1 grow, -1 shrink, 0 settle to rest. Frame-rate independent: every term
// scales with dtSec, and heldSec accumulates real elapsed time.
export function stepScale(
  s: ScaleState,
  dtSec: number,
  dir: -1 | 0 | 1,
  p: ScaleParams,
): ScaleState {
  const ramp = p.accelSec > 0 ? smootherstep(s.heldSec / p.accelSec) : 1;
  const speed = p.minLogVel + (p.maxLogVel - p.minLogVel) * ramp;
  const targetV = dir * speed;
  const alpha = p.tau > 0 ? 1 - Math.exp(-dtSec / p.tau) : 1;
  const logVel = s.logVel + (targetV - s.logVel) * alpha;
  const f = Math.exp(logVel * dtSec);
  const clamped = clampSize(s.w * f, s.h * f, p.minW, p.maxW, p.maxH);
  const heldSec = dir !== 0 ? s.heldSec + dtSec : s.heldSec;
  return { logVel, heldSec, w: clamped.w, h: clamped.h };
}
