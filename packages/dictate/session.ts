import { createState } from "ags";
import GLib from "gi://GLib";
import Gio from "gi://Gio";
import Soup from "gi://Soup?version=3.0";

// One dictation at a time, streamed to scribe's live ASR. Every press starts
// recording; how the key comes back up picks the mode:
//   tap  (released within HOLD_MS) → "toggle": words are typed into the focused
//         window as they become final, until the next press stops it.
//   hold                           → "hold": words show in the bubble and are
//         typed on release.
// Text is typed by Hyprland itself (send_shortcut), one key at a time with
// exactly the mods given. Synthetic keyboards like wtype don't work here:
// Hyprland merges held modifiers into their keys (a word typed while super is
// down fires super+1, super+Escape, ...) and XWayland apps read their keycodes
// against the real keymap, so text arrives as garbage.

const URL = "wss://scribe.lalala.casa/ws";
const RATE = 16000;
const HOLD_MS = 500;
// Give up on scribe's final words after this long and use what arrived.
const DONE_TIMEOUT_MS = 4000;

// US-layout key names for the characters dictation produces.
const UNSHIFTED: Record<string, string> = {
  " ": "space",
  ",": "comma",
  ".": "period",
  "'": "apostrophe",
  "-": "minus",
  "/": "slash",
  ";": "semicolon",
  "=": "equal",
  "[": "bracketleft",
  "]": "bracketright",
  "\\": "backslash",
  "`": "grave",
};
const SHIFTED: Record<string, string> = {
  "!": "1",
  "@": "2",
  "#": "3",
  $: "4",
  "%": "5",
  "^": "6",
  "&": "7",
  "*": "8",
  "(": "9",
  ")": "0",
  "?": "slash",
  ":": "semicolon",
  '"': "apostrophe",
  _: "minus",
  "+": "equal",
  "{": "bracketleft",
  "}": "bracketright",
  "|": "backslash",
  "~": "grave",
  "<": "comma",
  ">": "period",
};

export type Phase =
  "idle" | "pending" | "hold" | "toggle" | "finishing" | "error";

export const [phase, setPhase] = createState<Phase>("idle");
export const [label, setLabel] = createState("");
// The bubble's shape: a press starts "pending" (pill height, transcript
// width); it then animates to the three-line "hold" box or the "pill".
export type Shape = "pending" | "hold" | "pill";
export const [shape, setShape] = createState<Shape>("pending");

let mode: "pending" | "hold" | "toggle" = "pending";
let holdTimer = 0;
let recorder: Gio.Subprocess | null = null;
let conn: Soup.WebsocketConnection | null = null;
// Audio read before the socket opened, and whether the recorder has ended.
let backlog: Uint8Array[] = [];
let recorderDone = false;
let ended = false;
let doneTimer = 0;
let finishing = false;
let words: string[] = [];
let typed = 0;
let typing: Promise<void> = Promise.resolve();
// Bumped on reset, so callbacks from a finished session are ignored.
let generation = 0;

const run = (argv: string[], stdin?: string) =>
  new Promise<void>((resolve) => {
    try {
      // STDIN_PIPE only, never stdout/stderr pipes: wl-copy keeps inherited
      // pipes open while it serves the selection, so waiting would hang.
      const proc = Gio.Subprocess.new(
        argv,
        stdin === undefined
          ? Gio.SubprocessFlags.NONE
          : Gio.SubprocessFlags.STDIN_PIPE,
      );
      proc.communicate_utf8_async(stdin ?? null, null, () => resolve());
    } catch (e) {
      console.error(`dictate: ${argv[0]} failed`, e);
      resolve();
    }
  });

const keyFor = (c: string): [string, string] | null => {
  if (/[a-z0-9]/.test(c)) return ["", c];
  if (/[A-Z]/.test(c)) return ["SHIFT", c.toLowerCase()];
  if (c in UNSHIFTED) return ["", UNSHIFTED[c]];
  if (c in SHIFTED) return ["SHIFT", SHIFTED[c]];
  return null;
};

const shortcut = (mods: string, key: string) =>
  `hl.dispatch(hl.dsp.send_shortcut({ mods = "${mods}", key = "${key}", window = "active" }))`;

// Into the focused window, one hyprctl call per chunk. A chunk with characters
// the layout can't type (é, —) is pasted instead.
function send(text: string): Promise<void> {
  const keys = [...text].map(keyFor);
  if (keys.every((k) => k !== null))
    return run([
      "hyprctl",
      "eval",
      keys.map((k) => shortcut(...(k as [string, string]))).join(" "),
    ]);
  return run(["wl-copy"], text).then(() =>
    run(["hyprctl", "eval", shortcut("CTRL SHIFT", "v")]),
  );
}

function show() {
  if (mode === "toggle") setLabel("Dictating · tap again to stop");
  else setLabel(words.join(" ") || "Listening…");
}

// Type words [typed, n) into the focused window, in order.
function typeUpTo(n: number) {
  if (n <= typed) return;
  const text = words
    .slice(typed, n)
    .map((w, i) => (typed + i > 0 ? " " : "") + w)
    .join("");
  typed = n;
  typing = typing.then(() => send(text));
}

function onMessage(text: string) {
  const msg = JSON.parse(text);
  if (msg.type === "words") {
    words = words
      .slice(0, msg.from)
      .concat(msg.words.map((w: { word: string }) => w.word));
    // Every word but the last is final; the last may still grow.
    if (mode === "toggle") typeUpTo(words.length - 1);
    show();
  } else if (msg.type === "done") {
    finish();
  }
}

function sendEnd() {
  if (!conn || !recorderDone || ended) return;
  for (const chunk of backlog) conn.send_binary(chunk);
  backlog = [];
  conn.send_text(JSON.stringify({ type: "end" }));
  ended = true;
  doneTimer = GLib.timeout_add(GLib.PRIORITY_DEFAULT, DONE_TIMEOUT_MS, () => {
    doneTimer = 0;
    finish();
    return GLib.SOURCE_REMOVE;
  });
}

function connect() {
  const gen = generation;
  const session = new Soup.Session();
  const message = Soup.Message.new("GET", URL);
  session.websocket_connect_async(
    message,
    null,
    null,
    GLib.PRIORITY_DEFAULT,
    null,
    (_s, res) => {
      if (gen !== generation) return;
      try {
        conn = session.websocket_connect_finish(res);
      } catch (e) {
        fail("scribe is unreachable", e);
        return;
      }
      conn.connect("message", (_c, type, bytes) => {
        if (gen === generation && type === Soup.WebsocketDataType.TEXT)
          onMessage(new TextDecoder().decode(bytes.toArray()));
      });
      conn.connect("closed", () => {
        if (gen === generation && !ended) fail("scribe closed the stream");
      });
      conn.send_text(JSON.stringify({ sampleRate: RATE }));
      for (const chunk of backlog) conn.send_binary(chunk);
      backlog = [];
      sendEnd();
    },
  );
}

function record() {
  const gen = generation;
  recorder = Gio.Subprocess.new(
    [
      "pw-record",
      "--raw",
      "--rate",
      String(RATE),
      "--channels",
      "1",
      "--format",
      "s16",
      "-",
    ],
    Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_SILENCE,
  );
  const out = recorder.get_stdout_pipe()!;
  // 100 ms of audio per read.
  const pump = () =>
    out.read_bytes_async(RATE / 5, GLib.PRIORITY_DEFAULT, null, (_o, res) => {
      const bytes = out.read_bytes_finish(res);
      if (gen !== generation) return;
      if (bytes.get_size() === 0) {
        recorderDone = true;
        sendEnd();
        return;
      }
      const chunk = bytes.toArray();
      if (conn) conn.send_binary(chunk);
      else backlog.push(chunk);
      pump();
    });
  pump();
}

function stopRecording() {
  setPhase("finishing");
  recorder?.send_signal(2);
}

async function finish() {
  if (phase.get() === "idle" || finishing) return;
  finishing = true;
  if (doneTimer) GLib.source_remove(doneTimer);
  doneTimer = 0;
  typeUpTo(words.length);
  await typing;
  reset();
}

function fail(why: string, err?: unknown) {
  console.error(`dictate: ${why}`, err ?? "");
  recorder?.force_exit();
  conn = null;
  setPhase("error");
  setLabel(why);
  GLib.timeout_add(GLib.PRIORITY_DEFAULT, 2000, () => {
    if (phase.get() === "error") reset();
    return GLib.SOURCE_REMOVE;
  });
}

function reset() {
  generation++;
  if (holdTimer) GLib.source_remove(holdTimer);
  holdTimer = 0;
  if (conn?.get_state() === Soup.WebsocketState.OPEN) conn.close(1000, null);
  conn = null;
  recorder = null;
  backlog = [];
  recorderDone = false;
  ended = false;
  finishing = false;
  words = [];
  typed = 0;
  setPhase("idle");
  setShape("pending");
  setLabel("");
}

export function press() {
  const p = phase.get();
  if (p === "toggle") {
    stopRecording();
    return;
  }
  if (p !== "idle") return;
  mode = "pending";
  setPhase("pending");
  show();
  record();
  connect();
  holdTimer = GLib.timeout_add(GLib.PRIORITY_DEFAULT, HOLD_MS, () => {
    holdTimer = 0;
    if (mode === "pending") {
      mode = "hold";
      setShape("hold");
      setPhase("hold");
    }
    return GLib.SOURCE_REMOVE;
  });
}

export function release() {
  if (phase.get() === "pending") {
    if (holdTimer) GLib.source_remove(holdTimer);
    holdTimer = 0;
    mode = "toggle";
    setShape("pill");
    setPhase("toggle");
    show();
    typeUpTo(words.length - 1);
  } else if (phase.get() === "hold") {
    stopRecording();
  }
}
