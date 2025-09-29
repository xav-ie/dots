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
          linear *= ${toString (level / 100.0)};
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
          float factor = ${toString (level / 100.0)};
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
          float redFactor = ${toString (redness / 100.0)};
          vec3 redResult = mix(c.rgb, vec3(c.r, 0.0, 0.0), redFactor);
          vec3 linear = pow(redResult, vec3(2.2));
          linear *= ${toString (brightness / 100.0)};
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

  brightnessFiles = lib.listToAttrs (
    map (level: {
      name = ".config/hypr/shaders/${toString level}.glsl";
      value.text = brightnessShader level;
    }) brightnessLevels
  );

  rednessFiles = lib.listToAttrs (
    map (level: {
      name = ".config/hypr/shaders/${toString level}-red.glsl";
      value.text = rednessShader level;
    }) brightnessLevels
  );

  combinedFiles = lib.listToAttrs (
    lib.flatten (
      map (
        redness:
        map (brightness: {
          name = ".config/hypr/shaders/${toString redness}-red-${toString brightness}.glsl";
          value.text = combinedShader redness brightness;
        }) brightnessLevels
      ) brightnessLevels
    )
  );
in
{
  config = {
    home.packages = [ pkgs.hyprshade ];
    home.file = brightnessFiles // rednessFiles // combinedFiles;
  };
}
