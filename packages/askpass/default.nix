# Standalone SUDO_ASKPASS helper, bundled into a gjs binary with AGS (Astal).
# sudo runs `askpass <prompt>`; it shows a keyboard-exclusive password prompt and
# prints the typed password to stdout (exit 0), or exits non-zero on
# cancel/timeout. Replaces the zenity helper; wired in
# nixosConfigurations/modules/sudo-askpass.nix.
{
  stdenv,
  wrapGAppsHook3,
  gobject-introspection,
  gjs,
  agsPackages,
  is-sshed,
  writeShellScript,
  # System UI font, threaded in from lib/fonts.nix so the prompt tracks the same
  # `sans` font as the rest of the GTK config (@FONT@ in style.scss).
  fontName,
}:
let
  # sudo hands the prompt in argv[1]. Two things to settle before the GUI runs:
  #   - over ssh there is no Wayland session, so the layer-shell window never
  #     maps and sudo blocks on it; read from the tty instead.
  #   - wrapGAppsHook *prefixes* GI_TYPELIB_PATH, so an ambient one wins over
  #     ours (this repo's devshell exports a bleeding GTK/glibc set) and gjs
  #     loads typelibs from a different glibc than the binary, which segfaults.
  #     Clearing it leaves the wrapper's own prefix, which is the whole value.
  #   - gtk4-layer-shell needs a Wayland display, but the caller's env often says
  #     otherwise: ghostty exports GDK_BACKEND=x11, and a tmux pane predating a
  #     re-attach carries a stale WAYLAND_DISPLAY. GDK would then open XWayland
  #     and the prompt maps as a tiled toplevel. This has to happen before gjs
  #     starts; the bundle's imports open the display before app code runs.
  dispatch = writeShellScript "askpass-dispatch" ''
    if [ "$(${is-sshed}/bin/is-sshed)" = true ]; then
      printf '%s' "$1" > /dev/tty
      read -rs password < /dev/tty
      printf '\n' > /dev/tty
      printf '%s\n' "$password"
      exit 0
    fi
    unset GI_TYPELIB_PATH
    if [ ! -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]; then
      for sock in "$XDG_RUNTIME_DIR"/wayland-[0-9]*; do
        [ -S "$sock" ] && export WAYLAND_DISPLAY="''${sock##*/}" && break
      done
    fi
    export GDK_BACKEND=wayland
    exec "$(dirname "$0")/askpass-gui" "$@"
  '';
in
stdenv.mkDerivation {
  name = "askpass";
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
  ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    ags bundle app.ts $out/bin/askpass
    runHook postInstall
  '';

  postFixup = ''
    mv $out/bin/askpass $out/bin/askpass-gui
    install -m755 ${dispatch} $out/bin/askpass
  '';
}
