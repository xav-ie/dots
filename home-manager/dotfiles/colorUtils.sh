#!/usr/bin/env bash
# set -e

# Usage with argument: getAverageImageColor "image.png"
# Usage with stdin: echo "image.png" | getAverageImageColor
getAverageImageColor() {
  local inputImage=$1
  [ "$inputImage" = "" ] && read -r inputImage

  convert "$inputImage" -scale 1x1! -format "%[pixel:u.p{0,0}]\n" info:- |
    awk -F "[(),%]" 'BEGIN {r=0; g=0; b=0; n=0} {r += $2; g += $4; b += $6; n++} END {printf("%02x%02x%02x\n", 255 * (r/n)/100, 255 * (g/n)/100, 255 * (b/n)/100)}'
}

# Usage with argument: hexToHSL "ffeeaa"
# Usage with stdin: echo "ffeeaa" | hexToHSL
hexToHSL() {
  local inputHex=$1
  [ "$inputHex" = "" ] && read -r inputHex

  R=$((16#${inputHex:0:2}))
  G=$((16#${inputHex:2:2}))
  B=$((16#${inputHex:4:2}))

  awk -v r="$R" -v g="$G" -v b="$B" 'BEGIN {
    r /= 255; g /= 255; b /= 255;
    max = (r > g ? r : g); max = (max > b ? max : b);
    min = (r < g ? r : g); min = (min < b ? min : b);
    delta = max - min;
    l = (max + min) / 2;

    if (delta == 0) {
      h = 0; s = 0;
    } else {
      if (l < 0.5) s = delta / (max + min);
      else s = delta / (2 - max - min);

      if (max == r) h = (g - b) / delta;
      else if (max == g) h = 2 + (b - r) / delta;
      else if (max == b) h = 4 + (r - g) / delta;

      h *= 60;
      if (h < 0) h += 360;
    }
    printf("%.6f %.6f %.6f\n", h, s, l);
  }'
}

# Usage with argument: hslToHex 30 100 50
# Usage with stdin: echo "30 100 50" | hslToHex
hslToHex() {
  local H=$1 S=$2 L=$3
  [ "$H" = "" ] && read -r H S L

  awk -v h="$H" -v s="$S" -v l="$L" '
  function hue2rgb(p, q, t) {
    if (t < 0) t += 1;
    if (t > 1) t -= 1;
    if (t < 1/6) return p + (q - p) * 6 * t;
    if (t < 1/2) return q;
    if (t < 2/3) return p + (q - p) * (2/3 - t) * 6;
    return p;
  }
  BEGIN {
    s = s * 1.0; l = l * 1.0;
    if (s <= 1) s *= 100;
    if (l <= 1) l *= 100;
    s /= 100; l /= 100;
    if (s == 0) {
      r = l; g = l; b = l;
    } else {
      if (l < 0.5) q = l * (1 + s);
      else q = (l + s) - (l * s);
      p = 2 * l - q;
      h /= 360;
      r = hue2rgb(p, q, h + 1/3);
      g = hue2rgb(p, q, h);
      b = hue2rgb(p, q, h - 1/3);
    }
    r = int(r * 255.999999);
    g = int(g * 255.999999);
    b = int(b * 255.999999);
    printf("%02x%02x%02x\n", r, g, b);
  }'
}

calculateOneTriadic() {
  local H=$1 S=$2 L=$3
  [ "$H" = "" ] && read -r H S L

  awk -v h="$H" -v s="$S" -v l="$L" 'BEGIN {
    newH = h + 120;
    if (newH >= 360) newH -= 360;
    printf("%.6f %.6f %.6f\n", newH, s, l);
  }'
}

fullSaturation() {
  local H=$1 S=$2 L=$3
  [ "$H" = "" ] && read -r H S L

  awk -v h="$H" -v l="$L" 'BEGIN {
    printf("%.6f %.6f %.6f\n", h, 1.0, l);
  }'
}

halfLightness() {
  local H=$1 S=$2 L=$3
  [ "$H" = "" ] && read -r H S L
  awk -v h="$H" -v s="$S" -v l="$L" 'BEGIN {
    printf("%.6f %.6f %.6f\n", h, s, 0.5);
  }'
}

invertLightness() {
  local H=$1 S=$2 L=$3
  [ "$H" = "" ] && read -r H S L

  awk -v h="$H" -v s="$S" -v l="$L" 'BEGIN {
    printf("%.6f %.6f %.6f\n", h, s, 1-l);
  }'
}

dark() {
  local H=$1 S=$2 L=$3
  [ "$H" = "" ] && read -r H S L

  awk -v h="$H" -v s="$S" -v l="$L" 'BEGIN {
    printf("%.6f %.6f %.6f\n", h, s, 0.05);
  }'
}

hexToRGB() {
  local hex=$1
  [ "$hex" = "" ] && read -r hex

  # hex=${hex:1}  # Strip the leading "#"
  R=$((16#${hex:0:2}))
  G=$((16#${hex:2:2}))
  B=$((16#${hex:4:2}))
  printf "%d %d %d\n" "$R" "$G" "$B"
}
