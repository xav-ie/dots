// App zoom (Ctrl +/- / Ctrl+0). Full UI zoom: rescale EVERY px in the compiled
// stylesheet by the factor (fonts, padding, sizes, radii, borders) and re-apply
// it, and scale the week grid's `HOUR_HEIGHT` by the same factor so its
// CSS-drawn hour lines and the JS-positioned events stay aligned. The grid's
// columns/gutter read `zoom` and rebuild when it changes. Icons (sized via
// per-widget pixelSize in JS) stay fixed.
import { createState } from "ags";
import app from "ags/gtk4/app";
import style from "./style.scss";
import * as db from "./db";
import { setHourScale } from "./datetime";

const MIN = 0.5;
const MAX = 2.5;
const STEP = 0.1;

db.init(); // ensure the settings table exists before reading the saved zoom

const clamp = (f: number) =>
  Math.max(MIN, Math.min(MAX, Math.round(f * 10) / 10));

const load = (): number => {
  const raw = parseFloat(db.getSetting("zoom"));
  return Number.isFinite(raw) ? clamp(raw) : 1;
};

export const [zoom, setZoomState] = createState(load());

// Apply the persisted scale to the grid geometry immediately (before WeekView's
// first render) so a zoomed launch lays out correctly. The CSS can only be
// applied once GTK is up (initZoom), but this is a plain variable so it's safe.
setHourScale(zoom.get());

// Scale every px length in the compiled stylesheet by `factor`.
function scaledCss(factor: number): string {
  return style.replace(
    /(-?\d*\.?\d+)px/g,
    (_m, n) => `${(parseFloat(n) * factor).toFixed(3)}px`,
  );
}

// WeekView registers how to read/restore the grid scroll so zoom can keep the
// same time-of-day in view across the rebuild a zoom triggers.
let scrollGet: (() => number) | null = null;
let scrollSet: ((value: number) => void) | null = null;
export function registerZoomScroll(
  get: () => number,
  set: (v: number) => void,
) {
  scrollGet = get;
  scrollSet = set;
}

function apply(factor: number) {
  const prev = zoom.get(); // still the old factor here
  const preScroll = scrollGet?.() ?? 0;
  setHourScale(factor);
  // reset=true swaps the previously applied stylesheet for the scaled one.
  app.apply_css(scaledCss(factor), true);
  // Bump the zoom signal last so the grid rebuilds reading the updated geometry.
  setZoomState(factor);
  // The grid's pixel height scaled by factor/prev, so scale the scroll offset to
  // match — keeping the same hour at the top instead of jumping to midnight.
  if (scrollSet && prev > 0) scrollSet((preScroll * factor) / prev);
}

function setZoom(factor: number) {
  const f = clamp(factor);
  db.setSetting("zoom", String(f));
  apply(f);
}

export const zoomIn = () => setZoom(zoom.get() + STEP);
export const zoomOut = () => setZoom(zoom.get() - STEP);
export const zoomReset = () => setZoom(1);

// Reactive icon/image size: `pixelSize={iconPx(14)}` scales the icon with zoom
// (icons are sized in JS, so the CSS rescale can't reach them). Returns a binding
// that updates the widget's pixel-size live when the zoom changes.
export const iconPx = (base: number) => zoom((z) => Math.round(base * z));

// Apply the persisted zoom's CSS once GTK is initialized (called from window
// setup). The grid geometry was already set at module load above.
export function initZoom() {
  if (zoom.get() !== 1) app.apply_css(scaledCss(zoom.get()), true);
}
