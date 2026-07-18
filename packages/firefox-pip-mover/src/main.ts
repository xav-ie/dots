// Firefox PiP mover — impure shell.
//
// Firefox 152's Picture-in-Picture window intermittently poisons the whole
// process's macOS accessibility tree, so external movers (AX, yabai, SkyLight)
// can't reliably reposition it. Instead this runs INSIDE Firefox (loaded as a
// chrome subscript by firefox.cfg): a loopback TCP listener receives an anchor
// command from the `move-pip` hotkey client and repositions/scales the PiP via
// the window's own APIs. All geometry math lives in the pure, unit-tested
// geometry.ts; this file is just the XPCOM glue + the requestAnimationFrame loop.

import {
  Anchor,
  AnchorEdges,
  HEdge,
  Rect,
  ScaleParams,
  ScaleState,
  VEdge,
  anchorMaxSize,
  anchoredPosition,
  atRest,
  clampSize,
  isAnchor,
  movePosition,
  pickEdges,
  quantizeSize,
  shouldGlide,
  snapPosition,
  stepScale,
} from "./geometry";

const Ci = Components.interfaces;
const Cc = Components.classes;
const Cu = Components.utils;

const PORT_BASE = 47100;
const PORT_COUNT = 4;

// Speed ACCELERATES while held: ramps from MIN to MAX over SCALE_ACCEL_SEC, so
// a tap is gentle/precise and a sustained hold zooms fast. MIN is high enough
// that even at the smallest size growth is >=1 point/frame from the start, which
// keeps the size stepping regular (no slow-start chunkiness).
const SCALE_MIN_PER_SEC = 2.2; // size multiplier/sec at the start of a hold
const SCALE_MAX_PER_SEC = 10.0; // cap after ramping up (long holds zoom fast)
const SCALE_ACCEL_SEC = 0.8; // time to ramp MIN -> MAX
const SCALE_TAU = 0.05; // per-frame velocity smoothing (s)
const SCALE_SETTLE_TAU = 0.06; // faster velocity decay during a release glide
const SCALE_KEEPALIVE_MS = 70; // steady: detect release crisply this long after last cmd
// First command of a hold gets a longer keep-alive to bridge the OS's ~210ms
// initial-key-repeat gap, so a hold feels connected from the first keydown
// instead of growing ~70ms then stalling until auto-repeat kicks in.
const SCALE_INITIAL_KEEPALIVE_MS = 240;
// On release: glide to a stop only after a genuinely fast sweep; otherwise hard
// stop (keeps small nudges crisp). Threshold/epsilon are in log-velocity.
const SCALE_GLIDE_THRESHOLD = Math.log(2.8);
const SCALE_REST_EPS = Math.log(1.02);
const MAX_DT = 0.05; // clamp frame dt so a stall can't lurch the size
const MIN_CSS_W = 160; // smallest PiP width (css px); height follows aspect
const MIN_LOG_VEL = Math.log(SCALE_MIN_PER_SEC);
const MAX_LOG_VEL = Math.log(SCALE_MAX_PER_SEC);

function err(msg: unknown): void {
  try {
    Cu.reportError("[pip-mover] " + msg);
  } catch (_) {}
}

// CoreGraphics cursor control via js-ctypes. During a scroll-drag we HIDE the
// cursor and warp its (still-present) location to follow the PiP, so the window
// keeps receiving wheel events even after it slides out from under the pointer;
// when the gesture ends we warp back to where it started and show it again, so
// the user's cursor never ends up stranded across the screen. Returns null if
// ctypes/CG is unavailable (then move-without-tracking is the graceful fallback).
let warpFn: ((x: number, y: number) => void) | null = null;
let hideCursorFn: (() => void) | null = null;
let showCursorFn: (() => void) | null = null;
let warpTried = false;
function getWarp(): ((x: number, y: number) => void) | null {
  if (warpTried) return warpFn;
  warpTried = true;
  try {
    let ctypes: any = null;
    try {
      ctypes = ChromeUtils.import("resource://gre/modules/ctypes.jsm").ctypes;
    } catch (_) {}
    if (!ctypes) {
      try {
        ctypes = ChromeUtils.importESModule(
          "resource://gre/modules/ctypes.sys.mjs",
        ).ctypes;
      } catch (_) {}
    }
    if (!ctypes) {
      return null;
    }
    const lib = ctypes.open(
      "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices",
    );
    const CGPoint = ctypes.StructType("CGPoint", [
      { x: ctypes.double },
      { y: ctypes.double },
    ]);
    const warp = lib.declare(
      "CGWarpMouseCursorPosition",
      ctypes.default_abi,
      ctypes.int32_t,
      CGPoint,
    );
    const mainDisplay = lib.declare(
      "CGMainDisplayID",
      ctypes.default_abi,
      ctypes.uint32_t,
    );
    const hide = lib.declare(
      "CGDisplayHideCursor",
      ctypes.default_abi,
      ctypes.int32_t,
      ctypes.uint32_t,
    );
    const show = lib.declare(
      "CGDisplayShowCursor",
      ctypes.default_abi,
      ctypes.int32_t,
      ctypes.uint32_t,
    );
    const did = mainDisplay();
    warpFn = (x: number, y: number) => {
      try {
        warp(CGPoint(x, y));
      } catch (_) {}
    };
    // hide/show are reference-counted; the caller balances exactly one of each
    // per gesture (guarded by Mover.cursorHidden).
    hideCursorFn = () => {
      try {
        hide(did);
      } catch (_) {}
    };
    showCursorFn = () => {
      try {
        show(did);
      } catch (_) {}
    };
  } catch (e) {
    err("cursor ctypes init failed: " + e);
    warpFn = null;
  }
  return warpFn;
}

// --- finding the PiP window --------------------------------------------------

// Cache the PiP window so we don't enumerate every window on every command
// (~60/s while holding). Revalidate cheaply via `.closed`; re-enumerate on miss.
let cachedPip: any = null;
function findPiP(): any {
  try {
    if (cachedPip && !cachedPip.closed) return cachedPip;
  } catch (_) {}
  cachedPip = null;
  const en = Services.ww.getWindowEnumerator();
  while (en.hasMoreElements()) {
    const w = en.getNext();
    try {
      if (String(w.location.href).includes("pictureinpicture")) {
        cachedPip = w;
        return w;
      }
    } catch (_) {}
  }
  return null;
}

function baseWindowOf(pip: any): any {
  try {
    return pip.docShell.treeOwner
      .QueryInterface(Ci.nsIInterfaceRequestor)
      .getInterface(Ci.nsIBaseWindow);
  } catch (_) {
    return null;
  }
}

function winRect(pip: any): Rect {
  return {
    x: pip.screenX,
    y: pip.screenY,
    w: pip.outerWidth,
    h: pip.outerHeight,
  };
}

function screenRect(pip: any): Rect {
  const s = pip.screen;
  return { x: s.availLeft, y: s.availTop, w: s.availWidth, h: s.availHeight };
}

// --- continuous hold-to-scale loop -------------------------------------------

// Everything applyGeom() needs to place the window — shared by the key-driven
// scaler and the pinch handler.
interface Geom {
  pip: any;
  bw: any;
  useBW: boolean;
  hx: HEdge;
  hy: VEdge;
  aspect: number; // locked w/h, so the shape can't shimmer while scaling
  grid: number; // device px per point; snap sizes here to avoid WindowServer re-snap
  edges: AnchorEdges;
  state: { w: number; h: number };
}

interface Scaler extends Geom {
  dir: -1 | 0 | 1; // 0 = gliding to a stop after release
  params: ScaleParams;
  state: ScaleState; // narrows Geom.state with the animation fields
  deadline: number;
  last: number;
}

let animId: number | null = null;
let animWin: any = null;
let scaler: Scaler | null = null;
let warnedFallback = false;
// Last geometry actually pushed to the OS in the current resize gesture, so a tick
// that quantizes to the same rect can skip the (synchronous, forced-repaint) native
// resize. Reset to null when a gesture starts. See applyGeom.
let lastGeom: Rect | null = null;

function cancelAnim(): void {
  if (animId !== null && animWin) {
    try {
      animWin.cancelAnimationFrame(animId);
    } catch (_) {}
  }
  animId = null;
  animWin = null;
  scaler = null;
}

function applyGeom(s: Geom): Rect {
  // Snap size to the grid (locked aspect) and snap the position too. A CENTER-
  // anchored axis is snapped to TWICE the grid so size/2 stays grid-aligned and
  // the anchor point holds exactly — otherwise size/2 alternates whole/half grid
  // and the center jitters ±1px per size step while resizing. Corner/edge axes
  // pin an edge, so the plain grid is already exact for them.
  const gw = s.hx === "middle" ? 2 * s.grid : s.grid;
  const gh = s.hy === "middle" ? 2 * s.grid : s.grid;
  const { w: wr, h: hr } = quantizeSize(s.state.w, s.state.h, s.aspect, gw, gh);
  const { x, y } = anchoredPosition(s.hx, s.hy, s.edges, wr, hr, s.grid);
  // Skip the native resize when the quantized geometry is unchanged. The ease runs
  // at ~125Hz but size snaps to the device-px grid, so most ticks land on the same
  // x/y/w/h as the previous frame — and every setPositionAndSize is a synchronous
  // [NSWindow setFrame:display:YES] (a forced repaint) on macOS regardless of whether
  // anything actually moved (nsCocoaWindow::DoResize ignores the repaint flag). Firing
  // it only when a grid line is crossed kills that per-frame reflow storm — the last
  // thing keeping the resize from feeling buttery. Cursor warp still gets the rect.
  const lg = lastGeom;
  if (lg && lg.x === x && lg.y === y && lg.w === wr && lg.h === hr) return lg;
  const r: Rect = { x, y, w: wr, h: hr };
  lastGeom = r;
  try {
    // flags=0 (NOT eRepaint=1): a size change with eRepaint forces the widget to
    // repaint at the new size before the compositor's video IOSurface catches up,
    // so the newly-grown region shows the PiP window's transparent background for
    // one frame — the window underneath flashes through. Dropping eRepaint lets the
    // resize ride the compositor's next commit (which already carries the video),
    // closing the gap. Move keeps eRepaint since its content/size never changes.
    if (s.useBW) s.bw.setPositionAndSize(x, y, wr, hr, 0);
    else {
      s.pip.resizeTo(wr, hr);
      s.pip.moveTo(x, y);
    }
  } catch (_) {}
  return r;
}

function scaleStep(): void {
  animId = null;
  const s = scaler;
  if (!s) {
    animWin = null;
    return;
  }
  if (s.pip.closed) {
    cancelAnim();
    return;
  }
  const now = s.pip.performance.now();
  if (s.dir !== 0 && now >= s.deadline) {
    // Key released. Glide to a stop only if we were moving fast (a big sweep);
    // otherwise stop crisply so small nudges land exactly.
    if (!shouldGlide(s.state.logVel, SCALE_GLIDE_THRESHOLD)) {
      cancelAnim();
      return;
    }
    s.dir = 0;
    s.params.tau = SCALE_SETTLE_TAU;
  }
  if (s.dir === 0 && atRest(s.state.logVel, SCALE_REST_EPS)) {
    cancelAnim();
    return;
  }
  const dt = Math.min((now - s.last) / 1000, MAX_DT);
  s.last = now;
  s.state = stepScale(s.state, dt, s.dir, s.params);
  applyGeom(s);
  try {
    animId = s.pip.requestAnimationFrame(scaleStep);
  } catch (_) {
    cancelAnim();
  }
}

interface Calib {
  bw: any;
  useBW: boolean;
  dpr: number;
  aspect: number;
  edges: AnchorEdges;
  bounds: { left: number; top: number; right: number; bottom: number };
  w0: number;
  h0: number;
  minW: number;
  maxW: number;
  maxH: number;
}

// Read the PiP's live geometry once and derive everything a resize needs: the
// device-px edges, the dpr/point grid, the locked aspect, and the anchor-aware
// size limits. Shared by the key-driven scaler and the pinch handler.
//
// Prefer nsIBaseWindow.setPositionAndSize (atomic move+resize, device px); it
// uses DEVICE pixels while screenX/outerWidth are CSS px, so derive the scale
// from the live geometry rather than trusting devicePixelRatio (mixed-DPI safe).
function calibrate(pip: any, hx: HEdge, hy: VEdge): Calib {
  const bw = baseWindowOf(pip);
  let useBW = false;
  let x0: number, y0: number, w0: number, h0: number;
  let dpr = 1;
  if (bw) {
    try {
      const ox: any = {},
        oy: any = {},
        ocx: any = {},
        ocy: any = {};
      bw.getPositionAndSize(ox, oy, ocx, ocy);
      x0 = ox.value;
      y0 = oy.value;
      w0 = ocx.value;
      h0 = ocy.value;
      dpr = w0 / pip.outerWidth;
      if (isFinite(dpr) && dpr > 0) useBW = true;
    } catch (_) {}
  }
  if (!useBW) {
    if (!warnedFallback) {
      warnedFallback = true;
      err("nsIBaseWindow unavailable; using moveTo/resizeTo");
    }
    x0 = pip.screenX;
    y0 = pip.screenY;
    w0 = pip.outerWidth;
    h0 = pip.outerHeight;
    dpr = 1;
  }
  // Snap the anchor coordinates to the point grid ONCE here. anchoredPosition
  // computes position = anchor − size×fraction and re-snaps to grid; if the anchor
  // itself is off-grid, that snap rounds differently as the size steps, so the
  // pinned edge/center jitters ±1px while resizing. Grid-aligning the anchor up
  // front (paired with the 2×grid size step on a centered axis) keeps it exact.
  const snap = (v: number) => Math.round(v / dpr) * dpr;
  const edges: AnchorEdges = {
    left: snap(x0!),
    right: snap(x0! + w0!),
    top: snap(y0!),
    bottom: snap(y0! + h0!),
    midX: snap(x0! + w0! / 2),
    midY: snap(y0! + h0! / 2),
  };
  // Screen available area in the same (device-px) units as `edges`. Cap growth
  // to what fits AT THIS ANCHOR so the window stops at the edge instead of
  // overshooting and getting shoved off-center by the menu-bar clamp.
  const sc = pip.screen;
  const bounds = {
    left: sc.availLeft * dpr,
    top: sc.availTop * dpr,
    right: (sc.availLeft + sc.availWidth) * dpr,
    bottom: (sc.availTop + sc.availHeight) * dpr,
  };
  const max = anchorMaxSize(hx, hy, edges, bounds);
  return {
    bw,
    useBW,
    dpr,
    aspect: w0! / h0!,
    edges,
    bounds,
    w0: w0!,
    h0: h0!,
    minW: MIN_CSS_W * dpr,
    maxW: max.maxW,
    maxH: max.maxH,
  };
}

// Start the loop, or — if it's already running — just update direction and
// extend the keep-alive deadline (a held key keeps it alive). The magnetized
// anchor is captured once, at the start of the hold.
function scaleCommand(pip: any, dir: -1 | 1, hx: HEdge, hy: VEdge): void {
  if (scaler && animWin && !scaler.pip.closed) {
    // Continuation of a hold: keep the loop alive. Restart acceleration on a
    // direction reversal (or when resuming from a release-glide), and restore
    // the normal smoothing in case we were mid-glide on the settle tau.
    if (dir !== scaler.dir) scaler.state.heldSec = 0;
    scaler.dir = dir;
    scaler.params.tau = SCALE_TAU;
    scaler.deadline = scaler.pip.performance.now() + SCALE_KEEPALIVE_MS;
    return;
  }
  cancelAnim();
  lastGeom = null; // new gesture: force the first frame to actually apply

  const g = calibrate(pip, hx, hy);
  const now = pip.performance.now();
  scaler = {
    pip,
    bw: g.bw,
    useBW: g.useBW,
    hx,
    hy,
    dir,
    aspect: g.aspect,
    grid: g.dpr,
    edges: g.edges,
    params: {
      minLogVel: MIN_LOG_VEL,
      maxLogVel: MAX_LOG_VEL,
      accelSec: SCALE_ACCEL_SEC,
      tau: SCALE_TAU,
      minW: g.minW,
      maxW: g.maxW,
      maxH: g.maxH,
    },
    state: { logVel: 0, heldSec: 0, w: g.w0, h: g.h0 },
    // Longer keep-alive on the FIRST command to bridge the OS key-repeat gap.
    deadline: now + SCALE_INITIAL_KEEPALIVE_MS,
    last: now,
  };
  animWin = pip;
  try {
    animId = pip.requestAnimationFrame(scaleStep);
  } catch (_) {
    cancelAnim();
  }
}

// --- pinch (resize) + swipe (move) -------------------------------------------
// Two-finger SCROLL on the PiP chrome window arrives as a plain `wheel` and
// drives a directional swipe that snaps the PiP across a 3x3 position grid.
// PINCH can't be captured here: macOS routes magnify gestures only to the
// frontmost app, never as a DOM/wheel event on a background window. So pinch is
// captured out-of-process by focusd's CGEventTap and fed in via the `pinch` UDP
// command (see pinchFromAgent), which scales the PiP about the cursor point.

const MOVE_TAU = 0.04; // follow smoothing (s) while dragging the window
const MOVE_IDLE_MS = 60; // end a drag session this long after the last scroll
const SNAP_THRESHOLD = 24; // points: magnet-snap when the free pos is this close
const PINCH_TAU = 0.06; // follow smoothing (s): actual size eases toward target
const PINCH_AGENT_MS = 250; // settle a pinch session this long after the last event

// A pinch captured out-of-process (focusd's MultitouchSupport recognizer) and
// streamed in over UDP. Each `pinch` carries a per-frame scale delta + the cursor
// point (used only to gate — is the cursor over the PiP). We accumulate a target
// size and EASE the actual size toward it (the lerp), scaling about the window's
// magnetized 3x3 anchor so a shrink pulls toward the nearest hotspot — the same
// anchored placement (via applyGeom) the keyboard grow/shrink uses.
interface AgentPinch extends Geom {
  minW: number;
  maxW: number;
  maxH: number;
  tgtW: number;
  tgtH: number;
  fx: number; // cursor's fractional position within the window, captured at start
  fy: number;
  cursorX: number; // last warped cursor position (points)
  cursorY: number;
  cursorHidden: boolean; // true between hideCursor and the balancing showCursor
  last: number;
  deadline: number;
}
let agentPinch: AgentPinch | null = null;
let agentPinchTimer: any = null;
// The ease can't use requestAnimationFrame: the pinch is driven by external UDP,
// not DOM events, so the PiP's refresh driver stays idle and rAF is throttled to a
// near-stop (the mover escapes this only because real scroll events keep the
// refresh driver ticking). A timer runs regardless — PRECISE_CAN_SKIP gives even,
// animation-grade intervals (unlike SLACK, which drifts/coalesces and looks jerky).
const PINCH_TICK_MS = 8;

// Keep the (hidden) cursor pinned to the same fractional spot inside the window as
// it resizes, so a shrink toward the magnetized anchor doesn't slide the PiP out
// from under the pointer — the pointer follows the window and stays over it.
function warpPinchCursor(p: AgentPinch, r: Rect): void {
  if (!p.cursorHidden || !warpFn) return;
  p.cursorX = (r.x + p.fx * r.w) / p.grid;
  p.cursorY = (r.y + p.fy * r.h) / p.grid;
  warpFn(p.cursorX, p.cursorY);
}

function agentPinchStop(): void {
  const p = agentPinch;
  if (agentPinchTimer) {
    try {
      agentPinchTimer.cancel();
    } catch (_) {}
  }
  agentPinchTimer = null;
  // Show the (hidden) cursor again over the resized window — single chokepoint for
  // every way a pinch ends, so the hide/show reference count stays balanced.
  if (p && p.cursorHidden) {
    p.cursorHidden = false;
    if (warpFn) warpFn(p.cursorX, p.cursorY);
    if (showCursorFn) showCursorFn();
  }
  agentPinch = null;
}

function agentPinchTick(): void {
  const p = agentPinch;
  if (!p || p.pip.closed) {
    agentPinchStop();
    return;
  }
  const now = p.pip.performance.now();
  const dt = Math.min((now - p.last) / 1000, MAX_DT);
  p.last = now;
  const a = PINCH_TAU > 0 ? 1 - Math.exp(-dt / PINCH_TAU) : 1;
  p.state.w += (p.tgtW - p.state.w) * a;
  p.state.h += (p.tgtH - p.state.h) * a;
  warpPinchCursor(p, applyGeom(p));
  const settled =
    Math.abs(p.state.w - p.tgtW) < 0.5 && Math.abs(p.state.h - p.tgtH) < 0.5;
  if (settled && now >= p.deadline) {
    p.state.w = p.tgtW;
    p.state.h = p.tgtH;
    warpPinchCursor(p, applyGeom(p));
    agentPinchStop();
  }
}

function pinchFromAgent(pip: any, delta: number, cx: number, cy: number): void {
  const now = pip.performance.now();
  let p = agentPinch;
  if (!p || p.pip !== pip || pip.closed) {
    // Gate: only if the cursor is over THIS PiP. cx/cy and pip.screenX/Y are both
    // global CSS points, so this compares cleanly across displays. focusd forwards
    // every system pinch blindly; only Firefox knows the PiP's exact bounds.
    if (
      cx < pip.screenX ||
      cx > pip.screenX + pip.outerWidth ||
      cy < pip.screenY ||
      cy > pip.screenY + pip.outerHeight
    ) {
      return;
    }
    cancelAnim(); // a pinch takes over from any key-driven grow/shrink
    moverStop(); // ...and any in-flight drag
    lastGeom = null; // new gesture: force the first frame to actually apply
    // Magnetized 3x3 anchor from the window's current position, so a shrink pulls
    // toward the nearest hotspot (corner/edge/center) rather than the cursor.
    const { hx, hy } = pickEdges(winRect(pip), screenRect(pip));
    const g = calibrate(pip, hx, hy);
    // Cursor's fractional position within the window; the loop warps the cursor to
    // hold this fraction as the window resizes/moves, keeping it over the PiP.
    const fx = Math.max(0, Math.min(1, (cx - pip.screenX) / pip.outerWidth));
    const fy = Math.max(0, Math.min(1, (cy - pip.screenY) / pip.outerHeight));
    p = agentPinch = {
      pip,
      bw: g.bw,
      useBW: g.useBW,
      hx,
      hy,
      aspect: g.aspect,
      grid: g.dpr,
      edges: g.edges,
      minW: g.minW,
      maxW: g.maxW,
      maxH: g.maxH,
      state: { w: g.w0, h: g.h0 },
      tgtW: g.w0,
      tgtH: g.h0,
      fx,
      fy,
      cursorX: cx,
      cursorY: cy,
      cursorHidden: false,
      last: now,
      deadline: 0,
    };
    // Hide the cursor for the duration of the pinch; agentPinchStop() shows it
    // again (over the resized window) when the gesture ends.
    if (getWarp() && hideCursorFn) {
      hideCursorFn();
      p.cursorHidden = true;
    }
  }
  const c = clampSize(
    p.tgtW * (1 + delta),
    p.tgtH * (1 + delta),
    p.minW,
    p.maxW,
    p.maxH,
  );
  p.tgtW = c.w;
  p.tgtH = c.h;
  p.deadline = now + PINCH_AGENT_MS;
  if (!agentPinchTimer) {
    p.last = now;
    const timer = Cc["@mozilla.org/timer;1"].createInstance(Ci.nsITimer);
    timer.initWithCallback(
      { notify: agentPinchTick },
      PINCH_TICK_MS,
      Ci.nsITimer.TYPE_REPEATING_PRECISE_CAN_SKIP,
    );
    agentPinchTimer = timer;
  }
}

// scroll-to-move: a two-finger scroll drags the PiP freely (the free target
// curX/curY follows the fingers) and magnet-snaps to a valid position when near
// one. A rAF loop eases the actual position toward the (snapped or free) target.
interface Mover {
  pip: any;
  bw: any;
  useBW: boolean;
  grid: number;
  w0: number;
  h0: number;
  win: Rect; // {0,0,w0,h0} — snapPosition only reads w/h
  screen: Rect; // available area in device px
  curX: number;
  curY: number; // free (un-snapped) target, follows the fingers
  tgtX: number;
  tgtY: number; // where the window eases to (snapped or free)
  state: { x: number; y: number }; // actual animated position
  cursorX: number;
  cursorY: number; // tracked cursor screen position (points), warped to follow
  cursorHidden: boolean; // true between hideCursor and the balancing showCursor
  last: number;
  deadline: number;
}

let mover: Mover | null = null;
let moverRaf: number | null = null;

function moverStop(): void {
  const m = mover;
  if (moverRaf !== null && m) {
    try {
      m.pip.cancelAnimationFrame(moverRaf);
    } catch (_) {}
  }
  moverRaf = null;
  // End of gesture: show the (hidden) cursor again, leaving it over the MOVED
  // window (the loop has been warping it to follow, so cursorX/cursorY is already
  // on the PiP). This keeps it positioned for the next scroll-move instead of
  // stranding it where the gesture began. Single chokepoint for every way a drag
  // can end (settle, anchor command, pinch, window close), so the hide/show
  // reference count stays balanced.
  if (m && m.cursorHidden) {
    m.cursorHidden = false;
    if (warpFn) warpFn(m.cursorX, m.cursorY);
    if (showCursorFn) showCursorFn();
  }
  mover = null;
}

function applyMove(m: Mover): void {
  const x = Math.round(m.state.x / m.grid) * m.grid;
  const y = Math.round(m.state.y / m.grid) * m.grid;
  try {
    if (m.useBW) m.bw.setPositionAndSize(x, y, m.w0, m.h0, true);
    else m.pip.moveTo(x, y);
  } catch (_) {}
}

function moverStep(): void {
  moverRaf = null;
  const m = mover;
  if (!m) return;
  if (m.pip.closed) {
    moverStop();
    return;
  }
  const now = m.pip.performance.now();
  const dt = Math.min((now - m.last) / 1000, MAX_DT);
  m.last = now;
  const ox = m.state.x;
  const oy = m.state.y;
  const a = MOVE_TAU > 0 ? 1 - Math.exp(-dt / MOVE_TAU) : 1;
  const warp = getWarp();
  // Hold the session alive until the idle deadline even once the window is at
  // its target. The deadline bridges the gaps between scroll bursts (and the
  // inertial/momentum tail of a flick) so the whole gesture stays ONE session.
  // If we stopped early, each momentum event would re-init and re-seed the
  // cursor from a STALE e.screenX (a trackpad scroll never moves the hardware
  // pointer), snapping the cursor back to where the gesture began.
  const atTarget =
    Math.abs(m.state.x - m.tgtX) < 0.5 && Math.abs(m.state.y - m.tgtY) < 0.5;
  const done = atTarget && now >= m.deadline;
  if (done) {
    m.state.x = m.tgtX;
    m.state.y = m.tgtY;
  } else {
    m.state.x += (m.tgtX - m.state.x) * a;
    m.state.y += (m.tgtY - m.state.y) * a;
  }
  applyMove(m);
  // Warp the cursor by the same delta (device px -> points) so it stays over the
  // window and keeps receiving scroll even as the window slides away.
  if (warp) {
    m.cursorX += (m.state.x - ox) / m.grid;
    m.cursorY += (m.state.y - oy) / m.grid;
    warp(m.cursorX, m.cursorY);
  }
  if (done) {
    moverStop();
    return;
  }
  try {
    moverRaf = m.pip.requestAnimationFrame(moverStep);
  } catch (_) {
    moverStop();
  }
}

function onScrollWheel(pip: any, e: any): void {
  if (!mover || mover.pip !== pip || mover.pip.closed) {
    cancelAnim();
    agentPinchStop(); // a drag takes over from any in-flight pinch
    const g = calibrate(pip, "left", "top"); // anchor irrelevant; we use raw pos
    const x0 = g.edges.left;
    const y0 = g.edges.top;
    mover = {
      pip,
      bw: g.bw,
      useBW: g.useBW,
      grid: g.dpr,
      w0: g.w0,
      h0: g.h0,
      win: { x: 0, y: 0, w: g.w0, h: g.h0 },
      screen: {
        x: g.bounds.left,
        y: g.bounds.top,
        w: g.bounds.right - g.bounds.left,
        h: g.bounds.bottom - g.bounds.top,
      },
      curX: x0,
      curY: y0,
      tgtX: x0,
      tgtY: y0,
      state: { x: x0, y: y0 },
      // Seed the tracked cursor from this event's screen position (points); the
      // loop warps it by the window's per-frame delta so it stays over the PiP.
      cursorX: e.screenX,
      cursorY: e.screenY,
      cursorHidden: false,
      last: pip.performance.now(),
      deadline: 0,
    };
    // Hide the cursor for the duration of the move; moverStop() shows it again
    // (over the moved window) when the gesture ends.
    if (getWarp() && hideCursorFn) {
      hideCursorFn();
      mover.cursorHidden = true;
    }
  }
  const m = mover;
  // Natural scrolling: fingers move the window (deltaY<0 => down). Convert the
  // CSS-px scroll delta to device px and keep the window fully on screen.
  m.curX = Math.max(
    m.screen.x,
    Math.min(m.screen.x + m.screen.w - m.w0, m.curX - e.deltaX * m.grid),
  );
  m.curY = Math.max(
    m.screen.y,
    Math.min(m.screen.y + m.screen.h - m.h0, m.curY - e.deltaY * m.grid),
  );
  const snap = snapPosition(
    m.curX,
    m.curY,
    m.win,
    m.screen,
    SNAP_THRESHOLD * m.grid,
  );
  m.tgtX = snap.x;
  m.tgtY = snap.y;
  m.deadline = pip.performance.now() + MOVE_IDLE_MS;
  if (moverRaf === null) {
    m.last = pip.performance.now();
    moverRaf = pip.requestAnimationFrame(moverStep);
  }
}

function attachPinch(pip: any): void {
  try {
    if (pip.__pipMoverPinch) return; // attach once per window
    pip.__pipMoverPinch = true;
    pip.addEventListener(
      "wheel",
      (e: any) => {
        // Always swallow the PiP's wheel: plain two-finger scroll is our
        // swipe-to-move; ctrl+wheel (a focused pinch surfaces as one) would
        // otherwise trigger Firefox's page-zoom on top of the tap-driven resize.
        try {
          e.preventDefault();
        } catch (_) {}
        if (!e.ctrlKey) onScrollWheel(pip, e);
      },
      { capture: true, passive: false },
    );
  } catch (e) {
    err("attachPinch: " + e);
  }
}

// Attach gesture handling to the PiP window now (if open) and to any that opens.
function setupPinch(): void {
  const existing = findPiP();
  if (existing) attachPinch(existing);
  Services.ww.registerNotification({
    observe(subject: any, topic: string) {
      if (topic !== "domwindowopened") return;
      try {
        subject.addEventListener(
          "load",
          () => {
            try {
              if (String(subject.location.href).includes("pictureinpicture")) {
                attachPinch(subject);
              }
            } catch (_) {}
          },
          { once: true },
        );
      } catch (_) {}
    },
  });
}

// --- command dispatch --------------------------------------------------------

function applyAnchor(anchor: Anchor): string {
  const pip = findPiP();
  if (!pip) return "nopip";
  agentPinchStop(); // a key command takes over from any in-flight pinch
  moverStop(); // ...and from any in-flight drag

  if (anchor === "grow" || anchor === "shrink") {
    const { hx, hy } = pickEdges(winRect(pip), screenRect(pip));
    scaleCommand(pip, anchor === "grow" ? 1 : -1, hx, hy);
    return "ok";
  }

  // Corner/edge snap: instant, and cancel any in-flight grow/shrink first.
  cancelAnim();
  const { x, y } = movePosition(anchor, winRect(pip), screenRect(pip));
  pip.moveTo(Math.round(x), Math.round(y));
  return "ok";
}

function onLine(line: string): string {
  const s = String(line).trim();
  // `pinch <delta> <cx> <cy>` — from focusd's magnify tap: scale delta and the
  // cursor's screen point (points). Scales the PiP about the cursor.
  if (s.startsWith("pinch ")) {
    const [, d, cx, cy] = s.split(/\s+/);
    const pip = findPiP();
    if (!pip) return "nopip";
    try {
      pinchFromAgent(pip, parseFloat(d), parseFloat(cx), parseFloat(cy));
      return "ok";
    } catch (e) {
      err("pinch: " + e);
      return "err";
    }
  }
  if (isAnchor(s)) {
    try {
      return applyAnchor(s);
    } catch (e) {
      err("apply " + s + ": " + e);
    }
  }
  return "err";
}

// --- loopback listener (UDP) -------------------------------------------------
// UDP, not TCP: skhd fires a fresh client per key-repeat (~60/s), and every TCP
// connection lingers ~30s in TIME_WAIT after closing — they pile into the
// hundreds during a sustained hold and choke the network stack (which is why the
// jank got worse the longer you held). UDP is connectionless: no handshake, no
// TIME_WAIT, near-zero per-message work. Occasional datagram loss is harmless —
// the animation is time-based, so the next repeat or the keep-alive covers a
// dropped command.

function start(): void {
  const sock = Cc["@mozilla.org/network/udp-socket;1"].createInstance(
    Ci.nsIUDPSocket,
  );
  const principal = Services.scriptSecurityManager.getSystemPrincipal();
  let bound = -1;
  for (let i = 0; i < PORT_COUNT; i++) {
    try {
      sock.init(PORT_BASE + i, true /* loopbackOnly */, principal);
      bound = PORT_BASE + i;
      break;
    } catch (_) {}
  }
  if (bound < 0) {
    err("no free udp port in range");
    return;
  }
  sock.asyncListen({
    onPacketReceived(_s: any, message: any) {
      try {
        const res = onLine(message.data);
        // outputStream sends a datagram back to the sender — this is the
        // "ok"/"nopip" the client reads to decide whether to skip the AX path.
        const out = message.outputStream;
        const msg = res + "\n";
        out.write(msg, msg.length);
      } catch (e) {
        err("packet: " + e);
      }
    },
    onStopListening() {},
  });
}

try {
  start();
} catch (e) {
  err(e);
}
try {
  setupPinch();
} catch (e) {
  err("pinch setup: " + e);
}
