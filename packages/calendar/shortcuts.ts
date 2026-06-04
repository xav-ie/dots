// Keyboard shortcuts, shared by the right-pane "Useful shortcuts" panel and the
// full "?" dialog. Keep in sync with the handlers in Calendar.tsx.
export interface Shortcut {
  name: string;
  keys: string[];
}
export interface ShortcutGroup {
  title: string;
  items: Shortcut[];
}

export const SHORTCUT_GROUPS: ShortcutGroup[] = [
  {
    title: "General",
    items: [
      { name: "Command menu", keys: ["Ctrl", "K"] },
      { name: "Meet with…", keys: ["P"] },
      { name: "Zoom in / out", keys: ["Ctrl", "+", "−"] },
      { name: "Reset zoom", keys: ["Ctrl", "0"] },
      { name: "All keyboard shortcuts", keys: ["?"] },
      { name: "Close / quit", keys: ["Esc"] },
    ],
  },
  {
    title: "Navigation",
    items: [
      { name: "Go to today", keys: ["T"] },
      { name: "Go to date…", keys: ["."] },
      { name: "Previous period", keys: ["←"] },
      { name: "Next period", keys: ["→"] },
      { name: "Day / Week / Month", keys: ["D", "W", "M"] },
      { name: "Toggle sidebar", keys: ["`"] },
    ],
  },
];

// A short, flat list for the right-pane panel.
export const PANEL_SHORTCUTS: Shortcut[] = [
  { name: "Command menu", keys: ["Ctrl", "K"] },
  { name: "Go to today", keys: ["T"] },
  { name: "Go to date…", keys: ["."] },
  { name: "Previous / next", keys: ["←", "→"] },
  { name: "Toggle sidebar", keys: ["`"] },
  { name: "All shortcuts", keys: ["?"] },
];
