/*!
 * xdusk / dots — hide the macOS traffic lights (window controls) in VS Code.
 *
 * Prepended to the Electron main-process entry (out/main.js). VS Code 1.9x+
 * ships this as an **ESM** module (package.json "type": "module"), so we bridge
 * to CJS built-ins via createRequire — a plain `require(...)` is undefined here
 * and fails silently (that was the original "hook never ran" bug).
 *
 * Registers `app.on("browser-window-created")` and hides the native window
 * buttons on every window (the lights are native NSWindow buttons, not
 * themeable/CSS-reachable). We re-hide on show/ready-to-show/fullscreen in case
 * VS Code's custom title bar re-enables them. Guarded so any Electron internals
 * change degrades to "lights visible", never a broken launch.
 *
 * This ONLY hides the traffic lights — the rest of the title bar (command
 * center etc.) stays normal. Fully removing the title bar is a dead end on the
 * immutable nix build; use windowed Zen Mode for that (see the zenMode.* keys
 * in vscode.nix).
 */
import { createRequire as __xdusk_createRequire } from "node:module";

(function () {
  try {
    if (process.platform !== "darwin") return;
    const require = __xdusk_createRequire(import.meta.url);
    const { app } = require("electron");
    if (!app || typeof app.on !== "function") return;

    const hide = (win) => {
      try {
        if (win && !win.isDestroyed()) win.setWindowButtonVisibility(false);
      } catch (e) {
        /* ignore */
      }
    };

    app.on("browser-window-created", (_event, win) => {
      hide(win);
      try {
        win.once("ready-to-show", () => hide(win));
        win.once("show", () => hide(win));
        win.on("enter-full-screen", () => hide(win));
        win.on("leave-full-screen", () => hide(win));
      } catch (e) {
        /* ignore */
      }
    });
  } catch (e) {
    /* leave the chrome alone if anything goes wrong */
  }
})();
