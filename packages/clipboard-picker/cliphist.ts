// Data layer over `cliphist`: list history, copy an entry back to the
// clipboard, decode image entries to thumbnails, and delete entries. cliphist's
// own commands are the source of truth (it already keeps history MRU-ordered),
// so this file only marshals between cliphist and the widget.
import GLib from "gi://GLib";
import Gio from "gi://Gio";

export interface ClipEntry {
  // The verbatim `cliphist list` line, `<id>\t<preview>`. cliphist decode/delete
  // both parse the leading id straight off this line, so we keep it intact and
  // feed it back on stdin rather than reconstructing anything.
  line: string;
  id: string;
  preview: string;
  // cliphist stores only images as binary; text is text. Its preview for a
  // binary payload is the literal `[[ binary data … ]]` marker.
  isImage: boolean;
}

// Pipe `input` to a command's stdin and resolve once it exits. The command
// vector is always a fixed literal — untrusted entry text travels on stdin, so
// there is no shell-injection surface even though we go through `bash -c` to
// build the cliphist pipeline.
function feed(argv: string[], input: string): Promise<void> {
  const proc = Gio.Subprocess.new(
    argv,
    Gio.SubprocessFlags.STDIN_PIPE | Gio.SubprocessFlags.STDERR_PIPE,
  );
  const bytes = new GLib.Bytes(new TextEncoder().encode(input));
  return new Promise((resolve, reject) => {
    proc.communicate_async(bytes, null, (_, res) => {
      try {
        proc.communicate_finish(res);
        if (proc.get_successful()) resolve();
        else reject(new Error(`clipboard-picker: ${argv.join(" ")} failed`));
      } catch (err) {
        reject(err);
      }
    });
  });
}

export function list(): ClipEntry[] {
  const proc = Gio.Subprocess.new(
    ["cliphist", "list"],
    Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE,
  );
  const [, out] = proc.communicate_utf8(null, null);
  if (!proc.get_successful() || !out) return [];
  return out
    .split("\n")
    .filter((line) => line.length > 0)
    .map((line) => {
      const tab = line.indexOf("\t");
      const id = tab === -1 ? line : line.slice(0, tab);
      const preview = tab === -1 ? line : line.slice(tab + 1);
      return { line, id, preview, isImage: preview.includes("[[ binary data") };
    });
}

// Decode the entry and put it on the Wayland clipboard. wl-copy daemonizes, so
// the pipeline exits promptly once the selection is owned.
export function copy(entry: ClipEntry): Promise<void> {
  return feed(["bash", "-c", "cliphist decode | wl-copy"], entry.line);
}

// Drop an entry from history. The widget removes it from its own list too, so
// this is fire-and-forget from the UI's point of view.
export function remove(entry: ClipEntry): Promise<void> {
  return feed(["cliphist", "delete"], entry.line);
}

// Decode an image entry to `path`. The path is ours (a temp file we name), so
// it is safe to interpolate as the redirect target via $1.
export function decodeToFile(entry: ClipEntry, path: string): Promise<void> {
  return feed(
    ["bash", "-c", 'cliphist decode > "$1"', "bash", path],
    entry.line,
  );
}
