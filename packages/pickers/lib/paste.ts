// Paste the just-copied selection into whichever window regains focus once the
// picker hides. The delay lets the layer surface give up its exclusive keyboard
// before wtype's virtual keyboard fires. Terminals paste text on ctrl+shift+v;
// images keep ctrl+v so terminal apps (Claude Code) read the clipboard themselves.
import GLib from "gi://GLib";
import { execAsync } from "ags/process";

const SCRIPT = `
if [ "$1" = text ] && hyprctl activewindow | grep -q '^\\s*class: com.mitchellh.ghostty$'; then
  wtype -M ctrl -M shift v -m shift -m ctrl
else
  wtype -M ctrl v -m ctrl
fi`;

export function pasteIntoFocused(kind: "text" | "image"): void {
  GLib.timeout_add(GLib.PRIORITY_DEFAULT, 150, () => {
    execAsync(["bash", "-c", SCRIPT, "bash", kind]).catch((err) =>
      console.error("spotlight: paste failed", err),
    );
    return GLib.SOURCE_REMOVE;
  });
}
