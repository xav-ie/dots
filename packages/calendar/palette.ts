// Single source of truth for the calendar color palette: the 24 Google Calendar
// colors (bold form), in Google's order. Everything derives from this map:
//   - the `Color` type (keyof),
//   - the CSS classes — style.scss's `$colors` map is GENERATED from this file at
//     build time (see default.nix postPatch), so the stylesheet can't drift,
//   - the hue matcher (gmap.ts) and the editor's color picker (EventInfo).
// Keep keys kebab-case (they become `.ev-<name>` classes) and one `name: "#hex"`
// per line — the build greps this shape.
export const PALETTE = {
  tomato: "#da5234",
  "cherry-blossom": "#d85675",
  radicchio: "#c05476",
  flamingo: "#d6837a",
  tangerine: "#e3683e",
  pumpkin: "#dd7835",
  mango: "#e0963c",
  banana: "#e7ba51",
  citron: "#d8be5e",
  avocado: "#bcc256",
  pistachio: "#85ad59",
  basil: "#489160",
  sage: "#55b080",
  eucalyptus: "#429a8e",
  peacock: "#4b99d2",
  cobalt: "#668be1",
  blueberry: "#6e72c3",
  lavender: "#828bc2",
  wisteria: "#ae9cce",
  amethyst: "#a479b1",
  grape: "#a75aba",
  cocoa: "#957367",
  birch: "#a5998c",
  graphite: "#7c7c7c",
} as const;

export type Color = keyof typeof PALETTE;

export const COLOR_NAMES = Object.keys(PALETTE) as Color[];

// Fallback color: the neutral, used when a calendar has no/desaturated color.
export const DEFAULT_COLOR: Color = "graphite";

// Distinct hue candidates for per-person assignment (everything but the neutral).
const PERSON_COLORS = COLOR_NAMES.filter((c) => c !== DEFAULT_COLOR);

// A stable, distinct color for a person, hashed from a key (email). Used to tint
// each invitee's busy-preview blocks + diamond so attendees are distinguishable.
export function personColor(key: string): Color {
  let h = 0;
  for (let i = 0; i < key.length; i++) h = (h * 31 + key.charCodeAt(i)) >>> 0;
  return PERSON_COLORS[h % PERSON_COLORS.length];
}

const chunk = <T>(arr: readonly T[], n: number): T[][] => {
  const out: T[][] = [];
  for (let i = 0; i < arr.length; i += n) out.push(arr.slice(i, i + n));
  return out;
};

// Editor color-picker layout: the calendar palette in rows of eight.
export const COLOR_ROWS = chunk(COLOR_NAMES, 8);

// App accent-color picker (sidebar footer): the built-in coral default first
// (a "reset" swatch, styled by .swatch.accent-default), then the full calendar
// palette. The default hex must match $accent-default / @define-color accent in
// style.scss. Laid out in rows of eight for the popover grid.
export const ACCENT_DEFAULT_HEX = "#eb5757";
export const ACCENT_OPTIONS: {
  hex: string;
  cls: string;
  label: string;
  // Pre-generated hicolor icon name for this accent (see default.nix); the tray
  // switches to it on a pick. The default reuses the built-in coral icon.
  icon: string;
}[] = [
  {
    hex: ACCENT_DEFAULT_HEX,
    cls: "accent-default",
    label: "Default",
    icon: "dots-calendar",
  },
  ...COLOR_NAMES.map((name) => ({
    hex: PALETTE[name],
    cls: `ev-${name}`,
    label: name,
    icon: `dots-calendar-${name}`,
  })),
];
export const ACCENT_ROWS = chunk(ACCENT_OPTIONS, 8);

// The pre-generated tray/app icon name for an accent hex; the default coral icon
// for an unrecognized one.
export function accentIcon(hex: string): string {
  const lc = hex.toLowerCase();
  return (
    ACCENT_OPTIONS.find((o) => o.hex.toLowerCase() === lc)?.icon ??
    "dots-calendar"
  );
}

// Google's separate EVENT-color palette (11 colors): event color OVERRIDES pick
// from this list, not the 24 calendar colors. Each maps to a Google event
// `colorId`. Names are a subset of the calendar palette (so they reuse the
// `.ev-<name>` classes for display). In Google's picker order.
export const EVENT_COLORS: { id: string; name: Color; hex: string }[] = [
  { id: "1", name: "lavender", hex: "#7986cb" },
  { id: "2", name: "sage", hex: "#33b679" },
  { id: "3", name: "grape", hex: "#8e24aa" },
  { id: "4", name: "flamingo", hex: "#e67c73" },
  { id: "5", name: "banana", hex: "#f6bf26" },
  { id: "6", name: "tangerine", hex: "#f4511e" },
  { id: "7", name: "peacock", hex: "#039be5" },
  { id: "8", name: "graphite", hex: "#616161" },
  { id: "9", name: "blueberry", hex: "#3f51b5" },
  { id: "10", name: "basil", hex: "#0b8043" },
  { id: "11", name: "tomato", hex: "#d50000" },
];
export const EVENT_COLOR_ROWS = chunk(
  EVENT_COLORS.map((c) => c.name),
  6,
);
const eventIdByName = new Map(EVENT_COLORS.map((c) => [c.name, c.id]));
const eventNameById = new Map(EVENT_COLORS.map((c) => [c.id, c.name]));
// Event-color name → Google colorId (undefined if the color isn't an event color).
export const eventColorId = (name: Color): string | undefined =>
  eventIdByName.get(name);
// Google event colorId → our color name.
export const eventColorName = (id: string): Color | undefined =>
  eventNameById.get(id);

// Collapse the 24 calendar colors down to the 11 Google EVENT colors by visual
// family. Events inherit their calendar's color, but the editor's color picker
// only offers these 11 — so an inherited color must land on a real event swatch
// (and show as selected). A pure hue match mis-buckets the sparse event palette
// (yellow-greens → yellow, browns → orange), so the families are explicit; the
// several blues collapse to peacock, etc. Any palette color not listed falls
// back to the nearest event color by hue (graphite if desaturated).
const EVENT_FAMILY: Partial<Record<Color, Color>> = {
  tomato: "tomato",
  "cherry-blossom": "flamingo",
  radicchio: "flamingo",
  flamingo: "flamingo",
  tangerine: "tangerine",
  pumpkin: "tangerine",
  mango: "tangerine",
  banana: "banana",
  citron: "banana",
  avocado: "sage",
  pistachio: "sage",
  basil: "basil",
  sage: "sage",
  eucalyptus: "sage",
  peacock: "peacock",
  cobalt: "peacock",
  blueberry: "peacock",
  lavender: "lavender",
  wisteria: "grape",
  amethyst: "grape",
  grape: "grape",
  cocoa: "graphite",
  birch: "graphite",
  graphite: "graphite",
};
const EVENT_HUE_CANDIDATES: [Color, string][] = EVENT_COLORS.map((c) => [
  c.name,
  c.hex,
]);
// The event-palette color an inherited (calendar) color renders as; ~identity
// when it's already an event color.
export const toEventColor = (c: Color): Color =>
  EVENT_FAMILY[c] ??
  nearestByHue(PALETTE[c], EVENT_HUE_CANDIDATES, DEFAULT_COLOR);

// Readable text color (#000/#fff) for a given background hex, by luminance —
// used when writing a calendar's foregroundColor to Google.
export function foregroundFor(hex: string): string {
  const r = parseInt(hex.slice(1, 3), 16);
  const g = parseInt(hex.slice(3, 5), 16);
  const b = parseInt(hex.slice(5, 7), 16);
  return 0.299 * r + 0.587 * g + 0.114 * b > 150 ? "#000000" : "#ffffff";
}

// --- hue matching (shared by Google read- and write-mapping) ----------------

export const rgbOf = (hex: string): [number, number, number] => [
  parseInt(hex.slice(1, 3), 16),
  parseInt(hex.slice(3, 5), 16),
  parseInt(hex.slice(5, 7), 16),
];

// Hue of an RGB triple in degrees (0 if achromatic).
export function hueOf([r, g, b]: [number, number, number]): number {
  r /= 255;
  g /= 255;
  b /= 255;
  const max = Math.max(r, g, b);
  const d = max - Math.min(r, g, b);
  if (d === 0) return 0;
  let h: number;
  if (max === r) h = ((g - b) / d) % 6;
  else if (max === g) h = (b - r) / d + 2;
  else h = (r - g) / d + 4;
  h *= 60;
  return h < 0 ? h + 360 : h;
}

// Pick the candidate key whose color is the nearest HUE to `hex` (Google's
// pastel/legacy palettes share their bold counterpart's hue). Desaturated or
// invalid inputs fall back. Used to bucket both calendar and event colors.
export function nearestByHue<K>(
  hex: string,
  candidates: [K, string][],
  fallback: K,
): K {
  if (!/^#[0-9a-f]{6}$/i.test(hex)) return fallback;
  const [r, g, b] = rgbOf(hex);
  const max = Math.max(r, g, b);
  const sat = max === 0 ? 0 : (max - Math.min(r, g, b)) / max;
  if (sat < 0.15) return fallback;
  const h = hueOf([r, g, b]);
  let best = fallback;
  let bestD = Infinity;
  for (const [k, chex] of candidates) {
    const ch = hueOf(rgbOf(chex));
    const diff = Math.abs(h - ch);
    const d = Math.min(diff, 360 - diff);
    if (d < bestD) {
      bestD = d;
      best = k;
    }
  }
  return best;
}
