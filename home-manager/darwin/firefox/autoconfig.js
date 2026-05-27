// Firefox autoconfig bootstrap — loads firefox.cfg from the app's Resources dir.
// Lives at Firefox.app/Contents/Resources/defaults/pref/autoconfig.js (symlinked
// from the dots repo by the firefox-autoconfig home-manager activation script).
pref("general.config.filename", "firefox.cfg");
pref("general.config.obscure_value", 0);
pref("general.config.sandbox_enabled", false);
