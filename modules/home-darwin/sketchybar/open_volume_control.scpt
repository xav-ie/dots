#!/usr/bin/osascript

-- Needs the Sound menu bar item (system.defaults.controlcenter.Sound) — one
-- AXPress opens the volume popover directly.
tell application "System Events" to tell process "ControlCenter" to perform action "AXPress" of (first menu bar item of menu bar 1 whose description is "Sound")
