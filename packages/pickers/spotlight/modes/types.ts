import { Astal, Gtk } from "ags/gtk4";

// Fixed inner height (px) that every mode's content fills, so App, Clipboard,
// Emoji, Bluetooth and Power all render at exactly the same height regardless of
// their header (a search entry vs. the bluetooth scan + power-toggle row). Each
// mode pins its outer box to this and lets a vexpand scroll absorb whatever the
// header costs, instead of pinning the scroll and letting header differences
// leak into the total.
export const PANEL_CONTENT_H = 552;

// Imperative handle a mode exposes to the Spotlight shell.
export interface ModeHandle {
  // Called when this mode becomes the active, visible one: refresh state (reload
  // frecency, re-read the clipboard, …) and focus the right widget.
  onShow(): void;
  // Synchronously move focus to this mode's primary widget. Called the instant
  // the shell switches in, so the focus border paints in the same frame the mode
  // box is revealed (onShow's idle grab is too late — it leaves one borderless
  // frame, a visible flicker). Optional: modes without an entry can skip it.
  focus?(): void;
  // Handle a key while this mode is active. Return true to consume it. Escape is
  // normally left unconsumed so the shell closes — but a mode may consume it to
  // back out of a sub-step first (e.g. the power confirm).
  onKey(
    keyval: number,
    mod: number,
    controller: Gtk.EventControllerKey,
  ): boolean | void;
}

export interface ModeProps {
  // Register this mode's handle with the shell.
  register: (handle: ModeHandle) => void;
  // Close (hide) the whole Spotlight window.
  close: () => void;
  // The Spotlight window, for focus-ancestry checks (null until built).
  getWin: () => Astal.Window | null;
}
