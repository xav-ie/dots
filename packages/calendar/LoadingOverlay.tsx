import { createComputed } from "ags";
import { Gtk } from "ags/gtk4";
import { ALL_DAY, EVENTS } from "./data";
import { rev } from "./eventIndex";
import { syncNow } from "./store";
import { syncFailed, syncing } from "./sync";
import { iconPx } from "./zoom";

// Shown over the grid only on first load: when the cache is still empty and a
// sync is in flight (spinner) or the first sync failed (retry). Once any event
// exists the grid speaks for itself, so this stays hidden.
export default function LoadingOverlay() {
  const empty = () => EVENTS.length + ALL_DAY.length === 0;
  const mode = createComputed(() => {
    rev(); // recompute when events land
    const loading = syncing();
    const failed = syncFailed();
    if (!empty()) return "hidden";
    if (failed) return "failed";
    if (loading) return "loading";
    return "hidden";
  });
  return (
    <box
      class="load-overlay"
      visible={mode((m) => m !== "hidden")}
      halign={Gtk.Align.CENTER}
      valign={Gtk.Align.CENTER}
      orientation={Gtk.Orientation.VERTICAL}
      spacing={12}
    >
      <Gtk.Spinner
        spinning
        visible={mode((m) => m === "loading")}
        widthRequest={iconPx(32)}
        heightRequest={iconPx(32)}
      />
      <label
        class="load-label muted"
        label={mode((m) =>
          m === "failed"
            ? "Couldn't load your calendars"
            : "Loading your calendars…",
        )}
      />
      <button
        class="load-retry"
        visible={mode((m) => m === "failed")}
        onClicked={() => void syncNow()}
      >
        <label label="Retry" />
      </button>
    </box>
  );
}
