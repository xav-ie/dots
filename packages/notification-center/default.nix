# AGS (Astal) notification daemon + control center, bundled into two standalone
# gjs binaries. `agsPackages` is inputs.ags.packages.<system>, re-exporting the
# astal libraries (io, astal4, notifd, mpris, wireplumber) alongside the ags CLI
# (default).
# Produces:
#   notification-center  — the resident daemon (owns org.freedesktop.Notifications;
#                          renders toast popups + the control center), run as the
#                          `notification-center` systemd user service.
#   notifctl             — swaync-client-compatible CLI (status/-swb, toggle, DND)
#                          used by the bar, hypridle and screencast-dnd.
{
  stdenv,
  wrapGAppsHook3,
  gobject-introspection,
  gjs,
  agsPackages,
  # The weather widget shells out to curl (wttr.in).
  curl,
  # The screen-filter widget drives hyprshade (toggles the generated GLSL
  # warmth/brightness shaders from modules/home-linux/hyprland/hyprshade.nix).
  hyprshade,
  # System UI font family, threaded in from lib/fonts.nix so the center tracks
  # the same `sans` font as the bar and pickers.
  fontName,
}:
stdenv.mkDerivation {
  name = "notification-center";
  src = ./.;

  postPatch = ''
    substituteInPlace style.scss --replace-fail "@FONT@" "${fontName}"
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
    agsPackages.notifd
    agsPackages.mpris
    agsPackages.wireplumber
  ];

  # notifctl re-invokes its sibling `notification-center` (single-instance argv
  # forwarding) to toggle the control center, so put $out/bin on the wrapper PATH;
  # curl is for the weather widget, hyprshade for the screen-filter widget.
  preFixup = ''
    gappsWrapperArgs+=(--prefix PATH : "$out/bin:${curl}/bin:${hyprshade}/bin")
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    ags bundle app.ts $out/bin/notification-center
    # notifctl imports no GTK module, so the version can't be inferred — it's a
    # plain gjs CLI; pin it to satisfy the bundler.
    ags bundle notifctl.ts $out/bin/notifctl --gtk 4
    runHook postInstall
  '';
}
