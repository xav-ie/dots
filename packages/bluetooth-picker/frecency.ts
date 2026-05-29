// Frecency store for the bluetooth picker: a JSON map of device address ->
// { count, last } persisted under $XDG_STATE_HOME. `score` combines how often a
// device was connected with how recently, so daily-driver devices float to the
// top while one-off pairings sink.
import GLib from "gi://GLib";
import { readFile, writeFile } from "ags/file";

const STATE_FILE = `${GLib.get_user_state_dir()}/bluetooth-picker/frecency.json`;

export interface Entry {
  count: number;
  last: number; // microseconds since epoch (GLib.get_real_time)
}

export type Store = Record<string, Entry>;

export function load(): Store {
  try {
    const parsed = JSON.parse(readFile(STATE_FILE));
    // Guard against valid-but-wrong-shape JSON (truncated write, manual edit)
    // so a corrupt file self-heals instead of throwing on every launch.
    if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
      return parsed as Store;
    }
  } catch {
    // unreadable or invalid JSON — fall through to an empty store
  }
  return {};
}

export function bump(address: string): void {
  const store = load();
  const entry = store[address] ?? { count: 0, last: 0 };
  store[address] = { count: entry.count + 1, last: GLib.get_real_time() };
  try {
    GLib.mkdir_with_parents(GLib.path_get_dirname(STATE_FILE), 0o755);
    writeFile(STATE_FILE, JSON.stringify(store));
  } catch (err) {
    console.error("bluetooth-picker: failed to persist frecency", err);
  }
}

export function score(store: Store, address: string): number {
  const entry = store[address];
  if (!entry) return 0;
  const ageHours = (GLib.get_real_time() - entry.last) / 1e6 / 3600;
  // Recency multiplier with a one-week half-life.
  const recency = Math.pow(0.5, ageHours / (24 * 7));
  return entry.count * (0.5 + recency);
}
