// Per-picker frecency store: a JSON map of key -> { count, last } persisted under
// $XDG_STATE_HOME/pickers/<name>-frecency.json. `score` blends how often a key
// was chosen with how recently (one-week recency half-life), so daily-drivers
// float to the top while one-offs sink. Shared by the bluetooth picker (keyed by
// device address) and the emoji picker (keyed by glyph).
import GLib from "gi://GLib";
import { readFile, writeFile } from "ags/file";

export interface Entry {
  count: number;
  last: number; // microseconds since epoch (GLib.get_real_time)
}

export type Store = Record<string, Entry>;

export interface Frecency {
  load(): Store;
  bump(key: string): void;
  score(store: Store, key: string): number;
}

export function frecencyStore(name: string): Frecency {
  const file = `${GLib.get_user_state_dir()}/pickers/${name}-frecency.json`;

  function load(): Store {
    try {
      const parsed = JSON.parse(readFile(file));
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

  function bump(key: string): void {
    const store = load();
    const entry = store[key] ?? { count: 0, last: 0 };
    store[key] = { count: entry.count + 1, last: GLib.get_real_time() };
    try {
      GLib.mkdir_with_parents(GLib.path_get_dirname(file), 0o755);
      writeFile(file, JSON.stringify(store));
    } catch (err) {
      console.error(`${name}-picker: failed to persist frecency`, err);
    }
  }

  function score(store: Store, key: string): number {
    const entry = store[key];
    if (!entry) return 0;
    const ageHours = (GLib.get_real_time() - entry.last) / 1e6 / 3600;
    // Recency multiplier with a one-week half-life.
    const recency = Math.pow(0.5, ageHours / (24 * 7));
    return entry.count * (0.5 + recency);
  }

  return { load, bump, score };
}
