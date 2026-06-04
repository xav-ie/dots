// Linux-only Firefox prefs, appended to the wrapper's mozilla.cfg via
// extraPrefsFiles. First line of an autoconfig file is ignored, but this is
// cat'd after firefox.cfg so any line is fine here.

// Scale the entire Firefox UI (chrome + content) 1.3x. devPixelsPerPx is a
// STRING pref; -1 means "auto" (follow the display). Linux-only on purpose:
// on macOS this would override Retina auto-scaling and render wrong.
defaultPref("layout.css.devPixelsPerPx", "1.3");
