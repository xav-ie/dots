import { createBinding, createComputed, For } from "ags";
import { Gtk } from "ags/gtk4";
import AstalHyprland from "gi://AstalHyprland";

// Live Hyprland workspace pills across all outputs: click activates a
// workspace, special/named workspaces (id <= 0) are hidden, the rest sort
// numerically.
export default function Workspaces() {
  const hypr = AstalHyprland.get_default();
  const workspaces = createBinding(hypr, "workspaces");
  const focused = createBinding(hypr, "focusedWorkspace");

  const shown = createComputed(() =>
    [...workspaces()].filter((w) => w.id > 0).sort((a, b) => a.id - b.id),
  );

  return (
    <box class="module workspaces" spacing={2}>
      <For each={shown}>
        {(ws: AstalHyprland.Workspace) => (
          <button
            class={focused((f) => (f && f.id === ws.id ? "active" : ""))}
            tooltipText={`Workspace ${ws.id}`}
            onClicked={() => hypr.dispatch("workspace", String(ws.id))}
          >
            <label label={String(ws.id)} />
          </button>
        )}
      </For>
    </box>
  ) as Gtk.Widget;
}
