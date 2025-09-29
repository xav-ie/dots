{ lib, pkgs, ... }:
let
  inherit ((import ../../../lib/fonts.nix { inherit lib pkgs; })) fonts;

  ghostty-dir = ".config/ghostty/";
  causticOpacity = if pkgs.stdenv.isDarwin then "0.075" else "0.01";

  # Generate font-feature lines from the features list
  fontFeatureLines = lib.concatMapStringsSep "\n" (
    feature: "font-feature = ${feature}"
  ) fonts.configs.ghostty.font-features;

  watersubtleShader =
    pkgs.writeText "watersubtle.glsl" # glsl
      ''
        // All code below taken from shadertoy and slightly tweaked to get a cool
        // purple smoky effect.
        // https://www.shadertoy.com/view/MdlXz8

        ///////////////////////////////////////////////////////////////////////////////

        // Found this on GLSL sandbox. I really liked it, changed a few things and made
        // it tileable.
        // :)
        // by David Hoskins.
        // https://www.youtube.com/channel/UCeWx-VDFmo0KpNE5RQjhfSw/featured
        // Original water turbulence effect by joltz0r
        #define TAU 6.28318530718
        #define MAX_ITER 6

        void mainImage(out vec4 fragColor, in vec2 fragCoord) {
            vec3 water_color = vec3(1.0, 1.0, 1.0) * 0.5;
            float time = iTime * 0.15 + 23.0;
            vec2 uv = fragCoord.xy / iResolution.xy;

            // Base texture without any perturbation
            vec2 base_uv = uv;

            vec2 p = mod(uv * TAU, TAU) - 250.0;
            vec2 i = vec2(p);
            float c = 1.0;
            float inten = 0.01;

            for (int n = 0; n < MAX_ITER; n++) {
                float t = time * (1.0 - (3.5 / float(n + 1)));
                i = p + vec2(cos(t - i.x) + sin(t + i.y), sin(t - i.y) + cos(t + i.x));
                c += 1.0 / length(vec2(p.x / (sin(i.x + t) / inten),
                                p.y / (cos(i.y + t) / inten)));
            }
            c /= float(MAX_ITER);
            c = 1.17 - pow(c, 1.2); // Smooth caustics
            // Apply blue tint to caustics
            vec3 caustic_color = vec3(1.0, 0.0, 2.0) * pow(abs(c), 20.0);

            // vec3 caustic_color = vec3(pow(abs(c), 20.0)) * 1.2; // Amplify caustics
            // brightness

            // Perturbation only for caustics, not base content
            vec2 caustic_tc = vec2(cos(c) - 0.75, sin(c) - 0.75) * 0.03;
            vec2 caustic_uv = clamp(uv + caustic_tc, 0.0, 1.0);

            vec4 terminalColor = texture(iChannel0, base_uv);

            // Blend caustics only on unpainted areas using caustic_opacity
            if (terminalColor.r != 0.0 || terminalColor.g != 0.0 ||
                    terminalColor.b != 0.0) {
                // Leave base color unchanged where it is painted
                fragColor = terminalColor;
            } else {
                // Blend caustics with opacity where base is unpainted
                // Adjust this value to control caustic visibility
                float caustic_opacity = ${causticOpacity};
                fragColor = mix(terminalColor, vec4(caustic_color, terminalColor.a),
                        caustic_opacity);
            }
        }
      '';
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
          custom-shader = ${watersubtleShader}

          cursor-style-blink = false
          background-opacity = 0.80
          background-blur-radius = 20
          background = 000000
          foreground = ffffff
          # theme = Abernathy
          # theme = Argonaut
          # theme = Monokai Remastered
          theme = ${./theme.sh}

          font-family = "${fonts.configs.ghostty.font-family-1}"
          font-family = "${fonts.configs.ghostty.font-family-2}"
          font-size = ${toString fonts.configs.ghostty.font-size}
          ${fontFeatureLines}

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
      "${ghostty-dir}/watersubtle.glsl".source = watersubtleShader;
      "${ghostty-dir}/worley.glsl".source = ./worley.glsl;
      "${ghostty-dir}/themes/Xavier".source = ./theme.sh;
    };
  };
}
