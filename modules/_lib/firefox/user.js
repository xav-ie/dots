// Firefox user.js — overrides applied at every Firefox startup.

// Enable the Browser Toolbox (Ctrl+Shift+Alt+I) for inspecting chrome UI.
user_pref("devtools.chrome.enabled", true);
user_pref("devtools.debugger.remote-enabled", true);
// Required to make userChrome.css load.
user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);
