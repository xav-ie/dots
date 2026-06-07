#define TAU 6.28318530718
#define MAX_ITER 3

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
  vec3 water_color = vec3(1.0, 1.0, 1.0) * 0.5;
  // Use iFrame to advance one step per render call
  // Multiply by 0.015 to control animation speed
  float time = float(iFrame) * 0.0025 + 23.0;
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
  c = 1.5 - pow(c, 0.7); // Smooth caustics
  // Apply purple tint to caustics
  vec3 caustic_color = vec3(1.0, 0.0, 2.0) * pow(abs(c), 12.0); // Reduced from 20

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
    float caustic_opacity = 0.01;
    fragColor = mix(terminalColor, vec4(caustic_color, terminalColor.a),
        caustic_opacity);
  }
}
