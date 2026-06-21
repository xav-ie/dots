// Firefox user.js — overrides applied at every Firefox startup.

// Enable the Browser Toolbox (Ctrl+Shift+Alt+I) for inspecting chrome UI.
user_pref("devtools.chrome.enabled", true);
user_pref("devtools.debugger.remote-enabled", true);
// Required to make userChrome.css load.
user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);

// macOS only (no-op on Linux): make the HTML5 fullscreen API — every video
// player's fullscreen button, in-video `f`, etc. — use Firefox's own fullscreen
// instead of macOS *native* fullscreen. Native fullscreen banishes the window to
// its own Space, which (a) plays the slide animation and (b) makes yabai sort it
// onto a higher-numbered space, so `lcmd+2`'s first/last window toggle lands on
// the wrong window. Non-native fullscreen keeps the window on the current Space,
// killing both problems while the fullscreen button keeps working as expected.
user_pref("full-screen-api.macos-native-full-screen", false);
