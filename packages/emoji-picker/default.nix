# AGS (Astal) emoji picker, bundled into a standalone gjs binary. Bound to
# $mainMod+E in hyprland, replacing rofimoji. `agsPackages` is
# inputs.ags.packages.<system>, which re-exports the astal libraries (io,
# astal4) alongside the ags CLI (default).
{
  lib,
  stdenv,
  wrapGAppsHook3,
  gobject-introspection,
  gjs,
  agsPackages,
  makeDesktopItem,
  copyDesktopItems,
  # Runtime: the chosen glyph goes onto the clipboard (wl-clipboard) and is
  # typed into the focused window (wtype) via bash.
  bash,
  wl-clipboard,
  wtype,
  # System UI font family, threaded in from lib/fonts.nix so the picker tracks
  # the same `sans` font as the rest of the GTK config.
  fontName,
}:
stdenv.mkDerivation {
  name = "emoji-picker";
  src = ./.;

  postPatch = ''
    substituteInPlace style.scss --replace-fail "@FONT@" "${fontName}"
  '';

  nativeBuildInputs = [
    wrapGAppsHook3
    gobject-introspection
    agsPackages.default
    copyDesktopItems
  ];

  # On GI_TYPELIB_PATH at runtime via the gobject-introspection setup hook.
  buildInputs = [
    gjs
    agsPackages.io
    agsPackages.astal4
  ];

  desktopItems = [
    (makeDesktopItem {
      name = "emoji-picker";
      desktopName = "Emoji Picker";
      exec = "emoji-picker";
      icon = "emoji-picker";
      comment = "Search and insert emoji";
      categories = [ "Utility" ];
      keywords = [
        "emoji"
        "emoticon"
        "smiley"
        "symbol"
        "unicode"
      ];
    })
  ];

  # The bundled gjs binary shells out to wl-copy/wtype through bash, so put
  # them on the wrapper's PATH.
  preFixup = ''
    gappsWrapperArgs+=(--prefix PATH : ${
      lib.makeBinPath [
        bash
        wl-clipboard
        wtype
      ]
    })
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    ags bundle app.ts $out/bin/emoji-picker
    install -Dm644 icon.svg $out/share/icons/hicolor/scalable/apps/emoji-picker.svg
    runHook postInstall
  '';
}
