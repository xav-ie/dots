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
        else reject(new Error(`spotlight/clipboard: ${argv.join(" ")} failed`));
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

// Decode an entry to its raw bytes via cliphist, or null when the id no longer
// resolves. cliphist ids are ephemeral — a re-copy dedupes an entry to a fresh
// id and the max-items cap evicts the oldest — so a snapshot id can be stale by
// the time the user picks. A stale id makes `cliphist decode` print "id N not
// found" and emit nothing; we must detect that here rather than let an empty
// stream reach wl-copy (which would silently CLEAR the clipboard).
function decodeBytes(line: string): Promise<GLib.Bytes | null> {
  const proc = Gio.Subprocess.new(
    ["cliphist", "decode"],
    Gio.SubprocessFlags.STDIN_PIPE |
      Gio.SubprocessFlags.STDOUT_PIPE |
      Gio.SubprocessFlags.STDERR_PIPE,
  );
  const stdin = new GLib.Bytes(new TextEncoder().encode(line));
  return new Promise((resolve, reject) => {
    proc.communicate_async(stdin, null, (_, res) => {
      try {
        const [, stdout] = proc.communicate_finish(res);
        if (!proc.get_successful() || !stdout || stdout.get_size() === 0) {
          resolve(null);
        } else {
          resolve(stdout);
        }
      } catch (err) {
        reject(err);
      }
    });
  });
}

// Own the Wayland selection with already-decoded bytes. STDIN-only on purpose:
// wl-copy forks a daemon that inherits and holds any piped stdout/stderr open to
// serve the selection, so a `communicate` that pipes either never sees EOF and
// hangs forever — the caller would then wait for the *next* copy to displace
// this one before its close fires (Enter appearing to need a second press).
// Piping only stdin resolves as soon as the foreground wl-copy exits, daemon
// owning the selection; the type is inferred from the bytes exactly as the old
// `cliphist decode | wl-copy` pipeline did.
function writeClipboard(bytes: GLib.Bytes): Promise<void> {
  const proc = Gio.Subprocess.new(["wl-copy"], Gio.SubprocessFlags.STDIN_PIPE);
  return new Promise((resolve, reject) => {
    proc.communicate_async(bytes, null, (_, res) => {
      try {
        proc.communicate_finish(res);
        if (proc.get_successful()) resolve();
        else reject(new Error("spotlight/clipboard: wl-copy failed"));
      } catch (err) {
        reject(err);
      }
    });
  });
}

// Decode the entry and put it on the Wayland clipboard. Returns false only when
// the entry is genuinely gone from history; crucially we never hand wl-copy an
// empty stream, which would wipe whatever the user had on the clipboard.
export async function copy(entry: ClipEntry): Promise<boolean> {
  let bytes = await decodeBytes(entry.line);
  if (!bytes) {
    // The snapshot id went stale between listing and pick (a re-copy dedupes the
    // entry to a fresh id, the cap evicts the oldest). Re-resolve the entry by
    // its content in a fresh listing and retry once, so the pick still lands on
    // the first Enter. Require an unambiguous match so a non-unique preview —
    // notably the shared "[[ binary data … ]]" image marker — can't ever copy
    // the wrong entry.
    const matches = list().filter(
      (e) => e.isImage === entry.isImage && e.preview === entry.preview,
    );
    if (matches.length === 1) bytes = await decodeBytes(matches[0].line);
  }
  if (!bytes) return false;
  await writeClipboard(bytes);
  return true;
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
