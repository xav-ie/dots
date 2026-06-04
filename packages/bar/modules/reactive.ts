// Small reactive helpers shared by the status modules.
import { createState, onCleanup } from "ags";
import GObject from "gi://GObject";

// Recompute `compute()` whenever any of the given GObjects emits a notify
// signal, returning a reactive accessor usable directly in JSX (e.g.
// `label={derived([net], () => ssid())}`). Nulls in `objs` are ignored so
// callers can pass optional sub-objects (network.wifi, audio.defaultSpeaker)
// without guarding. Signal handlers are torn down on widget cleanup.
export function derived<T>(
  objs: Array<GObject.Object | null | undefined>,
  compute: () => T,
) {
  const [value, setValue] = createState(compute());
  const handlers: Array<[GObject.Object, number]> = [];
  for (const obj of objs) {
    if (!obj) continue;
    const id = obj.connect("notify", () => setValue(compute()));
    handlers.push([obj, id]);
  }
  onCleanup(() => handlers.forEach(([obj, id]) => obj.disconnect(id)));
  return value;
}
