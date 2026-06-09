# AGS (Astal) status bar, bundled into a standalone gjs binary. `agsPackages`
# is inputs.ags.packages.<system>, re-exporting the astal service libraries
# (wireplumber, bluetooth, tray, hyprland, mpris, cava) alongside the
# ags CLI (default). Run as the `bar` systemd user service (see
# home-manager/linux/bar).
{
  lib,
  stdenv,
  wrapGAppsHook3,
  gobject-introspection,
  gjs,
  agsPackages,
  # System UI font family, threaded in from lib/fonts.nix so the bar tracks the
  # same `sans` font as the pickers.
  fontName,
  # Monospace family (lib/fonts.nix `mono`), used for the pomodoro countdown so
  # its digits stay fixed-width and the centre pill doesn't jitter as time ticks.
  monoFontName,
  # Sibling packages the bar shells out to (clicks). `pickers` provides
  # bin/spotlight (the power/bluetooth modules run `spotlight <mode>`);
  # `notification-center` provides bin/notifctl (notification status/toggle/DND).
  notification-center,
  pickers,
  uair-toggle-and-notify,
  virtual-headset-ctl,
  # bin/virtual-headset-panel: opened by the virtual-headset module's right-click.
  virtual-headset-panel,
  # bin/hyprwhspr-rs: the dictation module's click toggles recording via its
  # `record toggle` IPC client (talks to the running daemon; no GPU/whisper).
  hyprwhspr-rs,
  # Runtime tools spawned via execAsync/subprocess.
  pavucontrol,
  pulseaudio, # pactl, to resolve the default mic source for cava
  networkmanagerapplet, # nm-connection-editor
  uair, # uairctl
  cava, # mic visualizer
  bash, # `sh -c` retry loop for uairctl listen
  coreutils, # sleep, in that loop
}:
stdenv.mkDerivation {
  name = "bar";
  src = ./.;

  postPatch = ''
    substituteInPlace style.scss \
      --replace-fail "@FONT@" "${fontName}" \
      --replace-fail "@MONOFONT@" "${monoFontName}"
  '';

  nativeBuildInputs = [
    wrapGAppsHook3
    gobject-introspection
    agsPackages.default
  ];

  # On GI_TYPELIB_PATH at runtime via the gobject-introspection setup hook.
  buildInputs = [
    gjs
    agsPackages.io
    agsPackages.astal4
    agsPackages.wireplumber
    agsPackages.bluetooth
    agsPackages.tray
    agsPackages.hyprland
    agsPackages.mpris
    agsPackages.cava
  ];

  # The bundled gjs binary spawns these directly, so put them on the wrapper's
  # PATH.
  preFixup = ''
    gappsWrapperArgs+=(--prefix PATH : ${
      lib.makeBinPath [
        notification-center
        pickers
        uair-toggle-and-notify
        virtual-headset-ctl
        virtual-headset-panel
        hyprwhspr-rs
        pavucontrol
        pulseaudio
        networkmanagerapplet
        uair
        cava
        bash
        coreutils
      ]
    })
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    ags bundle app.ts $out/bin/bar
    install -Dm644 icon.svg $out/share/icons/hicolor/scalable/apps/bar.svg
    # Custom symbolic icons (e.g. the dictation diamond) the modules reference by
    # name; installed into hicolor so the icon theme resolves them at runtime via
    # the gApps-wrapped XDG_DATA_DIRS.
    install -Dm644 -t $out/share/icons/hicolor/scalable/actions icons/*-symbolic.svg
    runHook postInstall
  '';
}
