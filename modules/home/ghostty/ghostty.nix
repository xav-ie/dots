{
  flake.modules.homeManager.common =
    {
      config,
      lib,
      pkgs,
      fonts,
      ...
    }:
    let
      ghosttyPath = "${config.dotFilesDir}/modules/home/ghostty";
      ghostty-dir = "ghostty";

      # Generate font-feature lines from the features list
      fontFeatureLines =
        fonts.configs.ghostty.font-features
        |> lib.concatMapStringsSep "\n" (feature: "font-feature = ${feature}");
    in
    {
      config = {
        # Linux takes bleeding's 1.3.1 (nixpkgs is on 1.2.3), run on Xwayland
        # against NVIDIA's native GL.
        #
        # Why not native Wayland: every Wayland client's EGL comes from Mesa
        # (NVIDIA's vendor doesn't offer the Wayland platform), and Mesa has no
        # native driver for this GPU — so it's zink or llvmpipe. Ghostty's cell
        # draw (instanced 4-vertex TRIANGLE_STRIP with an SSBO bound in the
        # vertex *and* fragment stages) hard-faults the GPU through zink here:
        # NVRM Xid 69, graphics-engine class error on Ampere class 0xc797,
        # after which the window never repaints — it reads as dead keyboard
        # input. Confirmed by tracing zink's draw stream at boot. llvmpipe
        # avoids the fault but burns ~250-400% CPU.
        #
        # On the X11 platform NVIDIA's EGL *does* serve us, so Xwayland gets
        # real GPU acceleration and can't hit the zink bug at all. Both vars are
        # needed: without the vendor pin Mesa wins on X11 and we land back on
        # llvmpipe. Trade-off is Xwayland's usual caveats (scaling, IME).
        # Revisit once the upstream zink/NVIDIA bug is fixed.
        programs.ghostty.package =
          if pkgs.stdenv.isLinux then
            pkgs.symlinkJoin {
              name = "ghostty-nvidia-x11";
              paths = [ pkgs.pkgs-bleeding.ghostty ];
              nativeBuildInputs = [ pkgs.makeWrapper ];
              postBuild = ''
                wrapProgram $out/bin/ghostty \
                  --set GDK_BACKEND x11 \
                  --set __EGL_VENDOR_LIBRARY_FILENAMES \
                    /run/opengl-driver/share/glvnd/egl_vendor.d/10_nvidia.json
              '';
              inherit (pkgs.pkgs-bleeding.ghostty) meta;
            }
          else
            pkgs.ghostty;

        xdg.configFile = lib.mkMerge [
          # Common config for all platforms
          {
            "${ghostty-dir}/config-nix".text = # sh
              ''
                # vim: set ft=sh:
                # Empty values reset the configuration to the default value
                ${lib.optionalString pkgs.stdenv.isDarwin ''
                  custom-shader = shaders/watersubtle-darwin.glsl
                  custom-shader-animation = true''}
                ${lib.optionalString pkgs.stdenv.isLinux "background-opacity = 0.95"}
                font-family = "${fonts.configs.ghostty.font-family-1}"
                font-family = "${fonts.configs.ghostty.font-family-2}"
                font-family = "${fonts.configs.ghostty.font-family-3}"
                font-size = ${fonts.configs.ghostty.font-size |> toString}
                ${fontFeatureLines}
              '';
            "${ghostty-dir}/config".source = config.lib.file.mkOutOfStoreSymlink "${ghosttyPath}/config.sh";

            # All water shader code below taken from shadertoy and slightly tweaked to get a cool
            # purple smoky effect.
            # https://www.shadertoy.com/view/MdlXz8
            # by David Hoskins.
            # https://www.youtube.com/channel/UCeWx-VDFmo0KpNE5RQjhfSw/featured
            # Original water turbulence effect by joltz0r
            "${ghostty-dir}/shaders/watersubtle-darwin.glsl".source =
              config.lib.file.mkOutOfStoreSymlink "${ghosttyPath}/shaders/watersubtle-darwin.glsl";
            "${ghostty-dir}/shaders/watersubtle-linux.glsl".source =
              config.lib.file.mkOutOfStoreSymlink "${ghosttyPath}/shaders/watersubtle-linux.glsl";
            "${ghostty-dir}/shaders/worley.glsl".source =
              config.lib.file.mkOutOfStoreSymlink "${ghosttyPath}/shaders/worley.glsl";
            "${ghostty-dir}/themes/XLight".source =
              config.lib.file.mkOutOfStoreSymlink "${ghosttyPath}/themes/XLight.sh";
            "${ghostty-dir}/themes/XDark".source =
              config.lib.file.mkOutOfStoreSymlink "${ghosttyPath}/themes/XDark.sh";
          }
        ];

        # Linux: Install via Nix package (macOS uses Homebrew cask in darwinConfigurations)
        home.packages = lib.optionals pkgs.stdenv.isLinux [ config.programs.ghostty.package ];
      };
    };
}
