#!/usr/bin/osascript -l JavaScript

// Open or close Notification Center, for the clock item's click.
//
// Pressing the clock's status item through accessibility opens it and closes
// it again 50ms later (the press's release reads as a second click), so this
// goes through Notification Center's own "Show Notification Center" shortcut,
// bound to F19 by sketchybar.nix. That shortcut only opens; Esc closes.

ObjC.import("CoreGraphics");

const F19 = 80;
const ESCAPE = 53;
const FUNCTION_KEY_FLAG = 0x800000;

function isOpen() {
  const windows = ObjC.deepUnwrap(
    ObjC.castRefToObject($.CGWindowListCopyWindowInfo(1, 0)),
  );
  return windows.some((w) => w.kCGWindowOwnerName === "Notification Center");
}

function press(keyCode, flags) {
  for (const down of [true, false]) {
    const e = $.CGEventCreateKeyboardEvent($(), keyCode, down);
    $.CGEventSetFlags(e, flags);
    $.CGEventPost(0, e);
  }
}

function run() {
  if (isOpen()) press(ESCAPE, 0);
  else press(F19, FUNCTION_KEY_FLAG);
}
