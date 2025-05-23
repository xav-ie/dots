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
          background-opacity = 0.80
          background-blur-radius = 20
          background = 000000
          foreground = ffffff
          # theme = Abernathy
          # theme = Argonaut
          # theme = Monokai Remastered
          theme = ${./theme.sh}

          font-family = "Maple Mono NF"
          font-family = "Apple Color Emoji"
          font-size = 15
          font-feature = cv01
          font-feature = cv02
          font-feature = ss01
          font-feature = ss02
          font-feature = ss03
          font-feature = ss04
          font-feature = ss05

          # I use zellij for maximum portability, so I don't want to depend on
          # Ghostty window management primitives.
          keybind = ctrl+shift+e=unbind
          keybind = ctrl+shift+n=unbind
          keybind = ctrl+shift+o=unbind
          keybind = ctrl+shift+t=unbind
          keybind = ctrl+comma=unbind
          keybind = ctrl+plus=increase_font_size:1
          keybind = ctrl+minus=decrease_font_size:1
        '';

      # Only here in order to make it easier to inspect shaders and theme
      "${ghostty-dir}/watersubtle.glsl".source = ./watersubtle.glsl;
      "${ghostty-dir}/underwater.glslsl".source = ./underwater.glsl;
      "${ghostty-dir}/worley.glsl".source = ./worley.glsl;
      "${ghostty-dir}/themes/Xavier".source = ./theme.sh;
    };
  };
}
