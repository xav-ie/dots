# AGS (Astal) clipboard picker, bundled into a standalone gjs binary. Bound to
# $mainMod+V in hyprland. `agsPackages` is inputs.ags.packages.<system>, which
# re-exports the astal libraries (io, astal4) alongside the ags CLI (default).
{
  lib,
  stdenv,
  wrapGAppsHook3,
  gobject-introspection,
  gjs,
  agsPackages,
  makeDesktopItem,
  copyDesktopItems,
  # Runtime: cliphist owns the history; wl-clipboard puts the choice back; the
  # decode pipeline runs through bash; coreutils' rm clears thumbnails.
  bash,
  cliphist,
  wl-clipboard,
  coreutils,
  # System UI font family, threaded in from lib/fonts.nix so the picker tracks
  # the same `sans` font as the rest of the GTK config.
  fontName,
}:
stdenv.mkDerivation {
  name = "clipboard-picker";
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
      name = "clipboard-picker";
      desktopName = "Clipboard Picker";
      exec = "clipboard-picker";
      icon = "clipboard-picker";
      comment = "Browse and paste clipboard history";
      categories = [ "Utility" ];
      keywords = [
        "clipboard"
        "clip"
        "paste"
        "history"
        "cliphist"
      ];
    })
  ];

  # The bundled gjs binary shells out to cliphist/wl-copy through bash, so put
  # them on the wrapper's PATH.
  preFixup = ''
    gappsWrapperArgs+=(--prefix PATH : ${
      lib.makeBinPath [
        bash
        cliphist
        wl-clipboard
        coreutils
      ]
    })
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    ags bundle app.ts $out/bin/clipboard-picker
    install -Dm644 icon.svg $out/share/icons/hicolor/scalable/apps/clipboard-picker.svg
    runHook postInstall
  '';
}
