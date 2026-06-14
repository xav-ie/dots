{
  flake.modules.homeManager.linux =
    { pkgs, lib, ... }:
    let
      brightnessShader =
        level: # glsl
        ''
          precision highp float;
          varying vec2 v_texcoord;
          uniform sampler2D tex;
          void main() {
              vec4 c = texture2D(tex, v_texcoord);
              vec3 linear = pow(c.rgb, vec3(2.2));
              linear *= ${(level / 100.0) |> toString};
              vec3 srgb = pow(linear, vec3(1.0/2.2));
              gl_FragColor = vec4(srgb, c.a);
          }
        '';

      rednessShader =
        level: # glsl
        ''
          precision highp float;
          varying vec2 v_texcoord;
          uniform sampler2D tex;
          void main() {
              vec4 c = texture2D(tex, v_texcoord);
              float factor = ${(level / 100.0) |> toString};
              vec3 result = mix(c.rgb, vec3(c.r, 0.0, 0.0), factor);
              gl_FragColor = vec4(result, c.a);
          }
        '';

      combinedShader =
        redness: brightness: # glsl
        ''
          precision highp float;
          varying vec2 v_texcoord;
          uniform sampler2D tex;
          void main() {
              vec4 c = texture2D(tex, v_texcoord);
              float redFactor = ${(redness / 100.0) |> toString};
              vec3 redResult = mix(c.rgb, vec3(c.r, 0.0, 0.0), redFactor);
              vec3 linear = pow(redResult, vec3(2.2));
              linear *= ${(brightness / 100.0) |> toString};
              vec3 srgb = pow(linear, vec3(1.0/2.2));
              gl_FragColor = vec4(srgb, c.a);
          }
        '';

      brightnessLevels = [
        0
        10
        20
        30
        40
        50
        60
        70
        80
        90
        100
      ];

      brightnessFiles =
        brightnessLevels
        |> map (level: {
          name = "hypr/shaders/${level |> toString}.glsl";
          value.text = level |> brightnessShader;
        })
        |> lib.listToAttrs;

      rednessFiles =
        brightnessLevels
        |> map (level: {
          name = "hypr/shaders/${level |> toString}-red.glsl";
          value.text = level |> rednessShader;
        })
        |> lib.listToAttrs;

      combinedFiles =
        brightnessLevels
        |> map (
          redness:
          brightnessLevels
          |> map (brightness: {
            name = "hypr/shaders/${redness |> toString}-red-${brightness |> toString}.glsl";
            value.text = combinedShader redness brightness;
          })
        )
        |> lib.flatten
        |> lib.listToAttrs;
    in
    {
      config = {
        home.packages = [ pkgs.hyprshade ];
        xdg.configFile = brightnessFiles // rednessFiles // combinedFiles;
      };
    };
}
