# AGS (Astal) launcher, bundled into a standalone gjs binary from a single source
# tree sharing one theme (lib/_theme.scss), window scaffold (lib/window.tsx) and
# frecency store (lib/frecency.ts). Produces one binary, `spotlight`: a resident,
# single-instance Spotlight-style launcher hosting the app/clipboard/emoji/
# bluetooth/power modes (each keybind messages it with a mode).
# `agsPackages` is inputs.ags.packages.<system>, re-exporting the astal libraries
# (io, astal4, apps, bluetooth) alongside the ags CLI (default).
{
  lib,
  stdenv,
  wrapGAppsHook3,
  gobject-introspection,
  gjs,
  agsPackages,
  makeDesktopItem,
  copyDesktopItems,
  # Runtime tools the bundled binaries shell out to: cliphist owns the clipboard
  # history; wl-clipboard puts the choice back; the decode pipeline and wl-copy
  # run through bash; coreutils' rm clears thumbnails; wtype types the chosen
  # emoji; power actions spawn systemctl/loginctl (systemd) and hyprctl (hyprland);
  # the bluetooth mode runs rfkill (util-linux) to unblock the adapter.
  bash,
  cliphist,
  wl-clipboard,
  coreutils,
  wtype,
  systemd,
  hyprland,
  util-linux,
  # System UI font family, threaded in from lib/fonts.nix so the pickers track
  # the same `sans` font as the rest of the GTK config.
  fontName,
}:
stdenv.mkDerivation {
  name = "pickers";
  src = ./.;

  # The font token lives once in the shared theme; every picker @use's it.
  postPatch = ''
    substituteInPlace lib/_theme.scss --replace-fail "@FONT@" "${fontName}"
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
    agsPackages.apps
    agsPackages.bluetooth
  ];

  desktopItems = [
    (makeDesktopItem {
      name = "spotlight";
      desktopName = "Spotlight";
      exec = "spotlight";
      icon = "spotlight";
      comment = "Search apps, clipboard, emoji, bluetooth and power actions";
      categories = [ "Utility" ];
      keywords = [
        "launcher"
        "spotlight"
        "app"
        "clipboard"
        "emoji"
        "bluetooth"
        "power"
        "run"
      ];
    })
  ];

  # The binary is wrapped with the union of the modes' runtime tools. They all
  # already live in the system closure, so the wider PATH costs nothing.
  preFixup = ''
    gappsWrapperArgs+=(--prefix PATH : ${
      lib.makeBinPath [
        bash
        cliphist
        wl-clipboard
        coreutils
        wtype
        systemd
        hyprland
        util-linux
      ]
    })
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    ags bundle spotlight/app.ts $out/bin/spotlight

    install -Dm644 spotlight/icon.svg \
      "$out/share/icons/hicolor/scalable/apps/spotlight.svg"
    runHook postInstall
  '';
}
