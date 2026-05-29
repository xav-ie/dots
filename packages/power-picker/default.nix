# AGS (Astal) power menu, bundled into a standalone gjs binary. Bound to
# $mainMod+Escape in hyprland and the waybar power button. `agsPackages` is
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
  # Runtime: power actions shell out to systemctl/loginctl (suspend, reboot,
  # poweroff, lock-session) and hyprctl (logout).
  systemd,
  hyprland,
  # System UI font family, threaded in from lib/fonts.nix so the picker tracks
  # the same `sans` font as the rest of the GTK config.
  fontName,
}:
stdenv.mkDerivation {
  name = "power-picker";
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
      name = "power-picker";
      desktopName = "Power Menu";
      exec = "power-picker";
      icon = "power-picker";
      comment = "Lock, suspend, log out, reboot or shut down";
      categories = [ "System" ];
      keywords = [
        "power"
        "shutdown"
        "reboot"
        "suspend"
        "logout"
        "lock"
      ];
    })
  ];

  # The bundled gjs binary spawns systemctl/loginctl/hyprctl directly, so put
  # them on the wrapper's PATH.
  preFixup = ''
    gappsWrapperArgs+=(--prefix PATH : ${
      lib.makeBinPath [
        systemd
        hyprland
      ]
    })
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    ags bundle app.ts $out/bin/power-picker
    install -Dm644 icon.svg $out/share/icons/hicolor/scalable/apps/power-picker.svg
    runHook postInstall
  '';
}
