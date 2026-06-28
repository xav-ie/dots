#!/usr/bin/osascript -l JavaScript
// @ts-check
/// <reference path="./jxa.d.ts" />

// Move a Chromium/Chrome Picture-in-Picture window (or the iPhone Mirroring
// window) around the current display via the macOS Accessibility API.
//
// Firefox is intentionally NOT handled here. Firefox 152's PiP window corrupts
// that process's ENTIRE accessibility tree (every window's AX attributes throw),
// so AX can neither read nor move it. Firefox PiP is moved out-of-band by a
// chrome-privileged TCP listener in firefox.cfg, which the `move-pip` wrapper
// pings alongside running this script. Chromium/Chrome expose the PiP to AX
// normally — only the window title differs ("Picture in Picture", spaces) — so
// they work fine here.
//
// Usage: move-pip <top-left|top-right|bottom-right|bottom-left
//                  |top-middle|middle-middle|bottom-middle|grow|shrink>

/** @typedef {{ x: number, y: number, w: number, h: number }} Rect */

/** @param {string[]} argv */
function run(argv) {
  const anchor = argv[0];
  ObjC.import("AppKit");
  const se = Application("System Events");

  // Chromium/Chrome title it "Picture in Picture"; match loosely to also cover
  // other Chromium forks and locale variants. (Firefox's hyphenated title would
  // match too, but Firefox processes are never queried here — broken AX.)
  const PIP_RE = /picture[\s-]?in[\s-]?picture/i;
  const BROWSERS = [
    "Chromium",
    "Google Chrome",
    "Google Chrome Canary",
    "Brave Browser",
    "Microsoft Edge",
    "Arc",
  ];

  /** @type {any} */
  let win = null;
  /** @type {any} */
  let proc = null;

  for (let b = 0; b < BROWSERS.length && !win; b++) {
    const procs = se.processes.whose({ name: BROWSERS[b] })();
    for (let i = 0; i < procs.length && !win; i++) {
      const ws = procs[i].windows();
      for (let j = 0; j < ws.length; j++) {
        let nm;
        try {
          nm = ws[j].name();
        } catch (e) {
          continue;
        }
        if (PIP_RE.test(nm)) {
          win = ws[j];
          proc = procs[i];
          break;
        }
      }
    }
  }
  if (!win) {
    const im = se.processes.byName("iPhone Mirroring");
    if (im.exists()) {
      win = im.windows[0];
      proc = im;
    }
  }
  // No AX-movable PiP present: Firefox (handled over TCP by the wrapper) may
  // hold it, or there's none open. Exit quietly rather than erroring.
  if (!win) return;

  // Apps exposing AXEnhancedUserInterface animate programmatic moves; off = instant.
  try {
    proc.attributes.byName("AXEnhancedUserInterface").value = false;
  } catch (e) {}

  const pos = /** @type {number[]} */ (win.position());
  const size = /** @type {number[]} */ (win.size());
  const x = pos[0],
    y = pos[1],
    w = size[0],
    h = size[1];
  const cx = x + w / 2,
    cy = y + h / 2;

  // Display frames in top-left-origin global coords (flip Cocoa around primary height).
  const screens = $.NSScreen.screens;
  const n = screens.count;
  let primaryH = 0;
  for (let i = 0; i < n; i++) {
    const f = screens.objectAtIndex(i).frame;
    if (f.origin.x === 0 && f.origin.y === 0) primaryH = f.size.height;
  }
  /** @type {Rect | null} */
  let chosen = null;
  /** @type {Rect | null} */
  let first = null;
  for (let i = 0; i < n; i++) {
    const f = screens.objectAtIndex(i).frame;
    const fr = /** @type {Rect} */ ({
      x: f.origin.x,
      y: primaryH - (f.origin.y + f.size.height),
      w: f.size.width,
      h: f.size.height,
    });
    if (i === 0) first = fr;
    if (cx >= fr.x && cx < fr.x + fr.w && cy >= fr.y && cy < fr.y + fr.h)
      chosen = fr;
  }
  if (!chosen) chosen = first;
  if (!chosen) throw new Error("No displays found.");
  const sx = chosen.x,
    sy = chosen.y,
    sw = chosen.w,
    sh = chosen.h;

  /** @param {number} nx @param {number} ny */
  const move = (nx, ny) => {
    win.position = [Math.round(nx), Math.round(ny)];
  };
  /** @param {number} nw @param {number} nh */
  const resize = (nw, nh) => {
    win.size = [Math.round(nw), Math.round(nh)];
  };

  switch (anchor) {
    case "top-left":
      move(sx, sy);
      break;
    case "top-right":
      move(sx + sw - w, sy);
      break;
    case "bottom-right":
      move(sx + sw - w, sy + sh - h);
      break;
    case "bottom-left":
      move(sx, sy + sh - h);
      break;
    case "top-middle":
      move(sx + (sw - w) / 2, sy);
      break;
    case "middle-middle":
      move(sx + (sw - w) / 2, sy + (sh - h) / 2);
      break;
    case "bottom-middle":
      move(sx + (sw - w) / 2, sy + sh - h);
      break;
    case "grow":
    case "shrink": {
      const factor = anchor === "grow" ? 0.1 : -0.1;
      const newW = w * (1 + factor),
        newH = h * (1 + factor);
      const ax =
        cx < sx + sw / 3 ? "left" : cx > sx + (sw * 2) / 3 ? "right" : "middle";
      const ay =
        cy < sy + sh / 3 ? "top" : cy > sy + (sh * 2) / 3 ? "bottom" : "middle";
      const nx =
        ax === "left" ? x : ax === "right" ? x + w - newW : x + (w - newW) / 2;
      const ny =
        ay === "top" ? y : ay === "bottom" ? y + h - newH : y + (h - newH) / 2;
      resize(newW, newH);
      move(nx, ny);
      break;
    }
    default:
      throw new Error("Unknown position: " + anchor);
  }
}
