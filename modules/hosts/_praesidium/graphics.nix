# hardware.graphics for praesidium. Called explicitly from _praesidium-body.nix
# (import-tree ignores `_`-prefixed paths), so it sits next to the patches it
# applies rather than in the global overlay.
#
# Firefox on Hyprland (wlroots) has no native-NVIDIA EGL path, so it renders
# through zink (Mesa-on-Vulkan). mesa 25.3.2's zink drops glyphs → unreadable
# text; fixed in mesa main. Build mesa main from the MAIN nixpkgs derivation so
# it links the system glibc (2.40) — building from bleeding instead links glibc
# 2.42, which needs GLIBC_ABI_GNU2_TLS, so every GL app fails to load mesa
# ("Unable to acquire the OpenGL context"). Bump rev + hash to move forward.
pkgs:
let
  inherit (pkgs) lib;
  # Only the two newer build deps mesa 26.x requires (libdrm >= 2.4.133,
  # directx-headers >= 1.619.1) come from bleeding — both glibc-safe (no
  # gnu2-TLS). Bump rev + hash to move forward.
  mesaMain =
    (pkgs.mesa.override {
      inherit (pkgs.pkgs-bleeding) libdrm;
      inherit (pkgs.pkgs-bleeding) directx-headers;
    }).overrideAttrs
      (old: {
        version = "26.4.0-git-5b7bcac";
        src = pkgs.fetchFromGitLab {
          domain = "gitlab.freedesktop.org";
          owner = "mesa";
          repo = "mesa";
          rev = "5b7bcac9bab7044034a6031fdf46ea803f92e861";
          hash = "sha256-y0kiSQi3MMgElu7NKwk0PGfSQ/YBz3AHWDbwFIiLD7E=";
        };
        # main nixpkgs' musl.patch (rocket driver) doesn't apply to 26.4 source.
        # + local zink/NVIDIA fixes: proper render-target usage for LINEAR-modifier
        # window buffers (GTK4 clients render), and no export handles on an imported
        # dma-buf (imported NVDEC surface would read back as zero — green video).
        patches = builtins.filter (p: !(lib.hasInfix "musl" (baseNameOf p))) (old.patches or [ ]) ++ [
          ./zink-nvidia-import-no-export.patch
        ];
      });
in
{
  enable = true;
  # Nothing on this host needs 32-bit GL, and package32 is deliberately left as
  # stock mesa — a 32-bit client would pick up zink (MESA_LOADER_DRIVER_OVERRIDE
  # is session-wide) without the fixes above. Flatpak is the only plausible one.
  enable32Bit = true;
  # zink glyph fix: pin the primary GL driver to mesa main.
  package = mesaMain;
  # VA-API (NVDEC) belongs in extraPackages, NOT `package`: `package` is the
  # primary GL/mesa driver, and overriding it with nvidia-vaapi-driver drops
  # the libglvnd dispatch libs (libGL/libEGL/libgbm) from /run/opengl-driver,
  # so GL apps fail with "Unable to acquire an opengl context".
  extraPackages = [
    # NVIDIA EGL external platforms, serving the Wayland (egl-wayland, EGLStream)
    # and GBM (egl-gbm) EGL platforms from nvidia. Load-bearing even though zink
    # drives GL: drop them and zink contexts die with `vkQueueSubmit failed
    # (VK_ERROR_DEVICE_LOST)` and the window freezes while still mapped and
    # focused, so it presents as broken input rather than a render bug. A
    # healthy zink start logs exactly one `DEVICE LOST`, which zink recovers
    # from; a vkQueueSubmit failure next to it is the real fault.
    # egl-gbm only exists in nixpkgs-bleeding.
    pkgs.pkgs-bleeding.egl-gbm
    pkgs.egl-wayland
    pkgs.nvidia-vaapi-driver # bumped to 0.0.17 in overlays/default.nix
  ];
}
