import { describe, expect, it } from "vitest";
import {
  AnchorEdges,
  MOVE_ANCHORS,
  Rect,
  ScaleParams,
  anchorMaxSize,
  anchoredPosition,
  atRest,
  clamp01,
  clampSize,
  isAnchor,
  isMoveAnchor,
  movePosition,
  pickEdges,
  snapPosition,
  quantizeSize,
  shouldGlide,
  smootherstep,
  stepScale,
} from "../src/geometry";

// A 1440x900 screen with a 25px menu bar at top (availTop = 25).
const SCREEN: Rect = { x: 0, y: 25, w: 1440, h: 875 };

describe("isAnchor", () => {
  it("accepts every valid anchor", () => {
    for (const a of [
      "top-left",
      "top-right",
      "bottom-right",
      "bottom-left",
      "top-middle",
      "middle-middle",
      "bottom-middle",
      "grow",
      "shrink",
    ]) {
      expect(isAnchor(a)).toBe(true);
    }
  });
  it("rejects junk", () => {
    expect(isAnchor("")).toBe(false);
    expect(isAnchor("growww")).toBe(false);
    expect(isAnchor("Picture-in-Picture")).toBe(false);
    expect(isAnchor("GROW")).toBe(false); // case-sensitive
    expect(isAnchor(" grow")).toBe(false); // caller trims before this
  });
});

describe("isMoveAnchor", () => {
  it("accepts the 7 move anchors but not grow/shrink", () => {
    for (const a of MOVE_ANCHORS) expect(isMoveAnchor(a)).toBe(true);
    expect(isMoveAnchor("grow")).toBe(false);
    expect(isMoveAnchor("shrink")).toBe(false);
    expect(isMoveAnchor("nonsense")).toBe(false);
  });
});

describe("pickEdges", () => {
  const win = (cx: number, cy: number): Rect => ({
    x: cx - 50,
    y: cy - 50,
    w: 100,
    h: 100,
  });
  it("classifies the center into screen thirds", () => {
    expect(pickEdges(win(100, 100), SCREEN)).toEqual({ hx: "left", hy: "top" });
    expect(pickEdges(win(720, 462), SCREEN)).toEqual({
      hx: "middle",
      hy: "middle",
    });
    expect(pickEdges(win(1400, 880), SCREEN)).toEqual({
      hx: "right",
      hy: "bottom",
    });
  });
  it("respects screen origin offset (availTop)", () => {
    // y just below availTop should be "top".
    expect(pickEdges(win(720, 40), SCREEN).hy).toBe("top");
  });
  it("works on a non-origin (second) monitor", () => {
    // A 1920x1080 screen offset to the right at x=1440.
    const ext: Rect = { x: 1440, y: 0, w: 1920, h: 1080 };
    expect(pickEdges(win(1440 + 100, 100), ext)).toEqual({
      hx: "left",
      hy: "top",
    });
    expect(pickEdges(win(1440 + 960, 540), ext)).toEqual({
      hx: "middle",
      hy: "middle",
    });
    expect(pickEdges(win(1440 + 1850, 1040), ext)).toEqual({
      hx: "right",
      hy: "bottom",
    });
  });
});

describe("movePosition", () => {
  const win: Rect = { x: 500, y: 500, w: 320, h: 180 };
  it("snaps to corners within the available rect", () => {
    expect(movePosition("top-left", win, SCREEN)).toEqual({ x: 0, y: 25 });
    expect(movePosition("top-right", win, SCREEN)).toEqual({ x: 1120, y: 25 });
    expect(movePosition("bottom-left", win, SCREEN)).toEqual({ x: 0, y: 720 });
    expect(movePosition("bottom-right", win, SCREEN)).toEqual({
      x: 1120,
      y: 720,
    });
  });
  it("centers for the middle anchors", () => {
    expect(movePosition("middle-middle", win, SCREEN)).toEqual({
      x: 560,
      y: 372.5,
    });
    expect(movePosition("top-middle", win, SCREEN)).toEqual({ x: 560, y: 25 });
    expect(movePosition("bottom-middle", win, SCREEN)).toEqual({
      x: 560,
      y: 720,
    });
  });
});

describe("snapPosition", () => {
  const screen: Rect = { x: 0, y: 25, w: 1440, h: 875 };
  const win: Rect = { x: 0, y: 0, w: 320, h: 180 };
  // anchors: top-left=(0,25), center=(560,372.5), bottom-right=(1120,720)
  it("snaps to a nearby anchor within threshold", () => {
    expect(snapPosition(8, 30, win, screen, 24)).toEqual({ x: 0, y: 25 });
  });
  it("leaves the position free when not near any anchor", () => {
    expect(snapPosition(400, 300, win, screen, 24)).toEqual({ x: 400, y: 300 });
  });
  it("picks the nearest in-range anchor (center)", () => {
    expect(snapPosition(555, 370, win, screen, 24)).toEqual({
      x: 560,
      y: 372.5,
    });
  });
  it("does not snap just outside the threshold", () => {
    // ~30px from top-left (0,25): beyond a 24 threshold
    expect(snapPosition(30, 25, win, screen, 24)).toEqual({ x: 30, y: 25 });
  });
});

describe("clampSize", () => {
  it("keeps a size that's already in range untouched", () => {
    expect(clampSize(320, 180, 160, 1440, 875)).toEqual({ w: 320, h: 180 });
  });
  it("clamps up to the min width, preserving aspect", () => {
    const r = clampSize(80, 45, 160, 1440, 875); // 16:9
    expect(r.w).toBe(160);
    expect(r.w / r.h).toBeCloseTo(16 / 9, 6);
  });
  it("clamps down to fit max bounds, preserving aspect", () => {
    const r = clampSize(4000, 2250, 160, 1440, 875); // 16:9, too big
    expect(r.w).toBeLessThanOrEqual(1440);
    expect(r.h).toBeLessThanOrEqual(875);
    expect(r.w / r.h).toBeCloseTo(16 / 9, 6);
  });
  it("clamps a very TALL window by height, not width", () => {
    // 9:16 portrait, taller than the screen: height is the binding constraint.
    const r = clampSize(900, 1600, 160, 1440, 875);
    expect(r.h).toBeCloseTo(875, 6);
    expect(r.w / r.h).toBeCloseTo(9 / 16, 6);
    expect(r.w).toBeLessThanOrEqual(1440);
  });
  it("preserves a non-16:9 aspect when clamping up to min", () => {
    const r = clampSize(40, 40, 160, 1440, 875); // square
    expect(r.w).toBe(160);
    expect(r.h).toBeCloseTo(160, 6); // stays square
  });
});

describe("anchoredPosition", () => {
  const edges: AnchorEdges = {
    left: 100,
    right: 500, // window currently spans x:100..500 (w=400)
    top: 50,
    bottom: 450, // y:50..450 (h=400)
    midX: 300,
    midY: 250,
  };
  it("pins the left/top edges exactly", () => {
    expect(anchoredPosition("left", "top", edges, 200, 200, 1)).toEqual({
      x: 100,
      y: 50,
    });
  });
  it("pins the right/bottom edges exactly regardless of new size", () => {
    // right edge must stay at 500, bottom at 450.
    const p = anchoredPosition("right", "bottom", edges, 200, 120, 1);
    expect(p.x + 200).toBe(500);
    expect(p.y + 120).toBe(450);
  });
  it("centers on the stored midpoints", () => {
    expect(anchoredPosition("middle", "middle", edges, 100, 100, 1)).toEqual({
      x: 250,
      y: 200,
    });
  });
  it("rounds the centered position to integer pixels", () => {
    // midX=300, w=101 -> 300-50.5 = 249.5 -> rounds to 250 (or 249); must be int.
    const p = anchoredPosition("middle", "middle", edges, 101, 101, 1);
    expect(Number.isInteger(p.x)).toBe(true);
    expect(Number.isInteger(p.y)).toBe(true);
  });
});

describe("anchorMaxSize", () => {
  // Screen available area: x 0..1440, y 25..900 (menu bar at top).
  const bounds = { left: 0, top: 25, right: 1440, bottom: 900 };
  const edges = (w: number, h: number, x: number, y: number): AnchorEdges => ({
    left: x,
    right: x + w,
    top: y,
    bottom: y + h,
    midX: x + w / 2,
    midY: y + h / 2,
  });

  it("a perfectly centered window can grow to fill the available area", () => {
    const e = edges(200, 100, 720 - 100, 462.5 - 50); // center at (720, 462.5) = avail center
    const m = anchorMaxSize("middle", "middle", e, bounds);
    expect(m.maxW).toBeCloseTo(1440, 6);
    expect(m.maxH).toBeCloseTo(875, 6);
  });

  it("an off-center (left-biased) middle window is capped by the nearer edge", () => {
    const e = edges(100, 60, 350, 400); // center x=400 -> nearer the left edge
    const m = anchorMaxSize("middle", "middle", e, bounds);
    expect(m.maxW).toBeCloseTo(2 * 400, 6); // 2 * (400 - 0)
  });

  it("a window near the TOP, growing about its center, is capped so its top can't pass the menu bar", () => {
    const e = edges(200, 100, 600, 75); // center y = 125 -> 100px below menu bar (25)
    const m = anchorMaxSize("middle", "middle", e, bounds);
    expect(m.maxH).toBeCloseTo(2 * (125 - 25), 6); // 200, not the full 875
  });

  it("edge anchors measure room from the pinned edge to the far side", () => {
    const e = edges(300, 170, 1140, 720); // bottom-right-ish
    const m = anchorMaxSize("right", "bottom", e, bounds);
    expect(m.maxW).toBeCloseTo(1140 + 300 - 0, 6); // right edge (1440) - avail.left (0)
    expect(m.maxH).toBeCloseTo(720 + 170 - 25, 6); // bottom edge (890) - avail.top (25)
  });

  it("never returns negative", () => {
    const e = edges(100, 100, -500, -500); // off-screen
    const m = anchorMaxSize("right", "bottom", e, bounds);
    expect(m.maxW).toBeGreaterThanOrEqual(0);
    expect(m.maxH).toBeGreaterThanOrEqual(0);
  });
});

describe("quantizeSize", () => {
  const aspect = 16 / 9;

  it("snaps both dims onto the device grid (whole points)", () => {
    const r = quantizeSize(370.6, 208.1, aspect, 2, 2); // dpr=2
    expect(r.w % 2).toBe(0);
    expect(r.h % 2).toBe(0);
  });

  it("derives height from the snapped width (aspect coherent, landscape)", () => {
    const r = quantizeSize(641.3, 360.9, aspect, 2, 2);
    expect(r.h).toBe(Math.round(r.w / aspect / 2) * 2);
  });

  it("drives off height for portrait aspect (<1)", () => {
    const port = 9 / 16;
    const r = quantizeSize(200.4, 360.7, port, 2, 2);
    expect(r.h % 2).toBe(0);
    expect(r.w).toBe(Math.round((r.h * port) / 2) * 2);
  });

  it("grid=1 gives integer points unchanged in spirit", () => {
    const r = quantizeSize(320.4, 180.2, aspect, 1, 1);
    expect(Number.isInteger(r.w)).toBe(true);
    expect(Number.isInteger(r.h)).toBe(true);
    expect(r.w).toBe(320);
  });

  it("does NOT shimmer: aspect stays within a hair across a growth sweep", () => {
    // The whole point — quantized aspect must not wobble more than the 1-point
    // grid forces. Sweep a continuous size range and bound the aspect spread.
    let min = Infinity;
    let max = -Infinity;
    for (let w = 320; w < 1200; w += 0.37) {
      const r = quantizeSize(w, w / aspect, aspect, 2, 2);
      const a = r.w / r.h;
      if (a < min) min = a;
      if (a > max) max = a;
    }
    // Independent rounding gave ~0.008 spread in the wild; locked+gridded is tighter.
    expect(max - min).toBeLessThan(0.02);
  });
});

describe("origin stability across a grow (the anti-jitter contract)", () => {
  const grid = 2; // dpr=2 (Retina): 1 point = 2 device px
  const aspect = 16 / 9;
  // Deliberately off-grid captured edges/center to stress the snapping.
  const e = {
    left: 101,
    right: 901,
    top: 99,
    bottom: 549,
    midX: 101 + 800 / 2,
    midY: 99 + 450 / 2,
  };

  it("middle/middle: the center stays within one point across the grow", () => {
    // 1pt size steps keep motion smooth; the centered position then has a ≤1pt
    // residual (size/2 alternates whole/half point) — the pixel-grid floor.
    const xs: number[] = [];
    const ys: number[] = [];
    for (let w = 200; w < 1400; w += 1.3) {
      const q = quantizeSize(w, w / aspect, aspect, grid, grid);
      const p = anchoredPosition("middle", "middle", e, q.w, q.h, grid);
      xs.push(p.x + q.w / 2);
      ys.push(p.y + q.h / 2);
    }
    expect(Math.max(...xs) - Math.min(...xs)).toBeLessThanOrEqual(grid);
    expect(Math.max(...ys) - Math.min(...ys)).toBeLessThanOrEqual(grid);
  });

  it("right/bottom: the pinned corner is pixel-stable the whole grow", () => {
    const corners = new Set<string>();
    for (let w = 200; w < 700; w += 1.3) {
      const q = quantizeSize(w, w / aspect, aspect, grid, grid); // edge axes -> 1pt
      const p = anchoredPosition("right", "bottom", e, q.w, q.h, grid);
      corners.add(`${p.x + q.w}:${p.y + q.h}`);
    }
    expect(corners.size).toBe(1);
  });

  it("left/top: the pinned corner is pixel-stable the whole grow", () => {
    const corners = new Set<string>();
    for (let w = 200; w < 700; w += 1.3) {
      const q = quantizeSize(w, w / aspect, aspect, grid, grid);
      const p = anchoredPosition("left", "top", e, q.w, q.h, grid);
      corners.add(`${p.x}:${p.y}`);
    }
    expect(corners.size).toBe(1);
  });

  it("positions land on the point grid (no WindowServer re-snap)", () => {
    const q = quantizeSize(513, 513 / aspect, aspect, grid, grid);
    const p = anchoredPosition("middle", "middle", e, q.w, q.h, grid);
    expect(p.x % grid).toBe(0);
    expect(p.y % grid).toBe(0);
  });
});

describe("shouldGlide / atRest", () => {
  const glide = Math.log(2.8);
  const rest = Math.log(1.02);
  it("glides only above the threshold (either direction)", () => {
    expect(shouldGlide(Math.log(5.0), glide)).toBe(true);
    expect(shouldGlide(-Math.log(5.0), glide)).toBe(true);
    expect(shouldGlide(Math.log(2.0), glide)).toBe(false);
    expect(shouldGlide(0, glide)).toBe(false);
  });
  it("atRest only when velocity is tiny", () => {
    expect(atRest(0, rest)).toBe(true);
    expect(atRest(Math.log(1.01), rest)).toBe(true);
    expect(atRest(Math.log(1.5), rest)).toBe(false);
  });
});

describe("smootherstep / clamp01", () => {
  it("clamp01 bounds to [0,1]", () => {
    expect(clamp01(-2)).toBe(0);
    expect(clamp01(0.3)).toBe(0.3);
    expect(clamp01(5)).toBe(1);
  });
  it("smootherstep hits the endpoints, midpoint, and is symmetric", () => {
    expect(smootherstep(0)).toBe(0);
    expect(smootherstep(1)).toBe(1);
    expect(smootherstep(0.5)).toBeCloseTo(0.5, 9);
    for (const t of [0.1, 0.27, 0.5, 0.8]) {
      expect(smootherstep(t) + smootherstep(1 - t)).toBeCloseTo(1, 9);
    }
  });
  it("smootherstep has ~zero slope at both ends (eased)", () => {
    const d = 1e-4;
    expect(smootherstep(d) / d).toBeLessThan(0.01); // slope at 0 ~ 0
    expect((1 - smootherstep(1 - d)) / d).toBeLessThan(0.01); // slope at 1 ~ 0
  });
});

describe("stepScale", () => {
  const params: ScaleParams = {
    minLogVel: Math.log(1.7),
    maxLogVel: Math.log(5.0),
    accelSec: 0.9,
    tau: 0.05,
    minW: 160,
    maxW: 1440,
    maxH: 875,
  };
  const frame = 1 / 60;
  const start = () => ({ logVel: 0, heldSec: 0, w: 320, h: 180 });

  it("grows over time and eases velocity in (no instant jump to full speed)", () => {
    let s = start();
    const firstVel = stepScale(s, frame, 1, params).logVel;
    expect(firstVel).toBeGreaterThan(0);
    expect(firstVel).toBeLessThan(params.maxLogVel);

    for (let t = 0; t < 30; t++) s = stepScale(s, frame, 1, params);
    expect(s.w).toBeGreaterThan(320);
    expect(s.logVel).toBeGreaterThan(firstVel);
    expect(s.logVel).toBeLessThanOrEqual(params.maxLogVel + 1e-9);
  });

  it("ACCELERATES the longer it's held (later velocity > earlier)", () => {
    let s = start();
    for (let t = 0; t < 12; t++) s = stepScale(s, frame, 1, params); // ~0.2s
    const early = s.logVel;
    for (let t = 0; t < 60; t++) s = stepScale(s, frame, 1, params); // ~1.2s total
    expect(s.logVel).toBeGreaterThan(early);
    // and it should approach the cap, not the min
    expect(s.logVel).toBeGreaterThan(params.minLogVel);
    expect(s.logVel).toBeLessThanOrEqual(params.maxLogVel + 1e-9);
  });

  it("a long hold grows super-linearly vs a short hold (acceleration)", () => {
    const grow = (secs: number) => {
      let s = start();
      for (let t = 0; t < Math.round(secs * 60); t++)
        s = stepScale(s, frame, 1, params);
      return Math.log(s.w / 320); // total log-growth
    };
    const short = grow(0.25);
    const long = grow(1.5);
    // 6x the time, but MORE than 6x the growth because speed ramped up.
    expect(long / short).toBeGreaterThan(6);
  });

  it("preserves aspect ratio while scaling", () => {
    let s = start();
    for (let t = 0; t < 20; t++) s = stepScale(s, frame, 1, params);
    expect(s.w / s.h).toBeCloseTo(320 / 180, 6);
  });

  it("shrinks toward, and clamps at, the min width", () => {
    let s = start();
    for (let t = 0; t < 600; t++) s = stepScale(s, frame, -1, params);
    expect(s.w).toBe(160);
    expect(s.w / s.h).toBeCloseTo(320 / 180, 6);
  });

  it("clamps at the max bounds when growing without limit", () => {
    let s = start();
    for (let t = 0; t < 600; t++) s = stepScale(s, frame, 1, params);
    expect(s.w).toBeLessThanOrEqual(1440);
    expect(s.h).toBeLessThanOrEqual(875);
  });

  it("is ~frame-rate independent (same elapsed time => ~same size)", () => {
    const grow = (steps: number, dt: number) => {
      let s = start();
      for (let i = 0; i < steps; i++) s = stepScale(s, dt, 1, params);
      return s.w;
    };
    const at60 = grow(60, 1 / 60);
    const at120 = grow(120, 1 / 120);
    expect(Math.abs(at120 - at60) / at60).toBeLessThan(0.01);
  });

  it("does not accumulate held time when settling (dir 0)", () => {
    let s = { logVel: Math.log(5.0), heldSec: 0.5, w: 320, h: 180 };
    const held0 = s.heldSec;
    for (let t = 0; t < 60; t++) s = stepScale(s, frame, 0, params);
    expect(s.heldSec).toBe(held0); // frozen while settling
    expect(Math.abs(s.logVel)).toBeLessThan(0.05); // decayed to rest
  });

  it("settles a SHRINKING (negative) velocity toward rest too", () => {
    let s = { logVel: -Math.log(5.0), heldSec: 0.5, w: 600, h: 337.5 };
    for (let t = 0; t < 60; t++) s = stepScale(s, frame, 0, params);
    expect(Math.abs(s.logVel)).toBeLessThan(0.05);
  });

  it("accelSec=0 jumps straight to the max-speed target (no ramp)", () => {
    const instant: ScaleParams = { ...params, accelSec: 0, tau: 0 };
    const s = stepScale(start(), frame, 1, instant);
    // tau=0 => velocity equals target immediately; accelSec=0 => target is max.
    expect(s.logVel).toBeCloseTo(params.maxLogVel, 9);
  });

  it("tau=0 makes velocity equal the (ramped) target each frame", () => {
    const p0: ScaleParams = { ...params, tau: 0 };
    let s = start();
    s = stepScale(s, frame, 1, p0); // heldSec ~ one frame, ramp ~0 => ~minLogVel
    expect(s.logVel).toBeGreaterThan(0);
    expect(s.logVel).toBeLessThan(params.maxLogVel);
  });

  it("a held direction reset (heldSec=0) returns to the slow start speed", () => {
    // Simulate a reversal: ramp up, then the shell would reset heldSec to 0.
    let s = start();
    for (let t = 0; t < 90; t++) s = stepScale(s, frame, 1, params); // ramped fast
    const fast = s.logVel;
    s = { ...s, heldSec: 0, logVel: 0 }; // shell reset on direction flip
    const afterReset = stepScale(s, frame, -1, params).logVel;
    expect(Math.abs(afterReset)).toBeLessThan(Math.abs(fast));
  });
});
