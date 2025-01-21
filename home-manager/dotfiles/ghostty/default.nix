_:
let
  ghostty-dir = ".config/ghostty/";
in
{
  config = {
    home.file = {
      "${ghostty-dir}/config".text = # sh
        ''
          # vim: set ft=sh:
          # Empty values reset the configuration to the default value
          copy-on-select = true
          quit-after-last-window-closed = true
          macos-option-as-alt = true
          macos-titlebar-style = hidden
          window-decoration = false
          title =" "
          custom-shader = ${./watersubtle.glsl}

          cursor-style-blink = false
          background-opacity = 0.75
          background-blur-radius = 15
          background = 000000
          foreground = ffffff
          # theme = Abernathy
          # theme = Argonaut
          # theme = Monokai Remastered
          theme = ${./theme.sh}

          font-family = Maple Mono NF
          font-size = 15
          font-feature = cv01
          font-feature = cv02
          font-feature = cv04
          font-feature = ss01
          font-feature = ss02
          font-feature = ss03
          font-feature = ss04
          font-feature = ss05
        '';

      # Only here in order to make it easier to inspect shaders and theme
      "${ghostty-dir}/watersubtle.glsl".source = ./watersubtle.glsl;
      "${ghostty-dir}/underwater.glslsl".source = ./underwater.glsl;
      "${ghostty-dir}/worley.glsl".source = ./worley.glsl;
      "${ghostty-dir}/themes/Xavier".source = ./theme.sh;
    };
  };
}
