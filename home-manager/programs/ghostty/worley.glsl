// Calculate the squared length of a vector
float length2(vec2 p) { return dot(p, p); }

// Generate some noise to scatter points
float noise(vec2 p) {
  return fract(sin(fract(sin(p.x) * (43.13311)) + p.y) * 31.0011);
}

float worley(vec2 p) {
  float d = 1e30;
  for (int xo = -1; xo <= 1; ++xo) {
    for (int yo = -1; yo <= 1; ++yo) {
      vec2 tp = floor(p) + vec2(xo, yo);
      d = min(d, length2(p - tp - noise(tp)));
    }
  }
  return 3.0 * exp(-4.0 * abs(2.5 * d - 1.0));
}

float fworley(vec2 p) {
  return sqrt(sqrt(sqrt(worley(p * 5.0 + 0.05 * iTime) *
                        sqrt(worley(p * 50.0 + 0.12 + -0.1 * iTime)) *
                        sqrt(sqrt(worley(p * -10.0 + 0.03 * iTime))))));
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
  vec2 uv = fragCoord.xy / iResolution.xy;
  float t = fworley(uv * iResolution.xy / 1500.0);
  t *= exp(-length2(abs(0.7 * uv - 1.0)));

  // Sample texture for blending
  vec4 terminalColor = texture(iChannel0, uv);

  // Blend texture color with procedural effect
  vec3 effectColor = t * vec3(0.1, 1.1 * t, pow(t, 0.5 - t));
  vec3 blendedColor = mix(terminalColor.rgb, effectColor, 0.25);

  if (terminalColor.r > 10.0 || terminalColor.g > 10.0 ||
      terminalColor.b > 10.0) {
    // Leave base color unchanged where it is painted
    fragColor = terminalColor;
  } else {
    // Blend caustics with opacity where base is unpainted
    float effect_opacity =
        0.5; // Adjust this value to control caustic visibility
    fragColor =
        mix(terminalColor, vec4(blendedColor, terminalColor.a), effect_opacity);
  }
}
