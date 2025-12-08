{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit ((import ../../../lib/fonts.nix { inherit lib pkgs; })) fonts;

  ghosttyPath = "${config.dotFilesDir}/home-manager/modules/ghostty";
  ghostty-dir = "ghostty";

  # Generate font-feature lines from the features list
  fontFeatureLines = lib.concatMapStringsSep "\n" (
    feature: "font-feature = ${feature}"
  ) fonts.configs.ghostty.font-features;
in
{
  config = {
    programs.ghostty.package = pkgs.ghostty;

    xdg.configFile = lib.mkMerge [
      # Common config for all platforms
      {
        "${ghostty-dir}/config-nix".text = # sh
          ''
            # vim: set ft=sh:
            # Empty values reset the configuration to the default value
            custom-shader = ${
              if pkgs.stdenv.isDarwin then "shaders/watersubtle-darwin.glsl" else "shaders/watersubtle-linux.glsl"
            }
            custom-shader-animation = ${if pkgs.stdenv.isDarwin then "true" else "false"}
            font-family = "${fonts.configs.ghostty.font-family-1}"
            font-family = "${fonts.configs.ghostty.font-family-2}"
            font-family = "${fonts.configs.ghostty.font-family-3}"
            font-size = ${toString fonts.configs.ghostty.font-size}
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
}
