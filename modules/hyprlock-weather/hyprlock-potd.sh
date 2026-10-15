# Bake the lock background: Bing picture of the day (refetched at most every 6h) with the Today/Tomorrow
# cards drawn in, sized to the hyprlock-weather labels hyprlock draws on top.
dir="${XDG_CACHE_HOME:-$HOME/.cache}/hyprlock"
mkdir -p "$dir"
if [[ ! -f $dir/potd.jpg || $(($(date +%s) - $(stat -c %Y "$dir/potd.jpg"))) -gt 21600 ]]; then
  meta=$(curl -fsS 'https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=1&mkt=en-US')
  curl -fsS -o "$dir/potd.jpg.tmp" "https://www.bing.com$(jq -r '.images[0].urlbase' <<<"$meta")_UHD.jpg"
  mv "$dir/potd.jpg.tmp" "$dir/potd.jpg"
  jq -r '.images[0] | "\(.title)\n\(.copyright)"' <<<"$meta" >"$dir/potd.txt"
fi

# Each card's height follows its column (weather + agenda), measured with the same pango hyprlock uses.
# markup goes through a file: inline pango: text mangles entities like &amp;
pango_h() {
  local f
  f=$(mktemp)
  printf "<span font='CaskaydiaCove Nerd Font Mono 38'>%s</span>" "$1" >"$f"
  magick -density 96 -background none pango:@"$f" -format %h info:
  rm -f "$f"
}
b0=$((($(pango_h "$(${weather} 0)") + 110) * 3 / 2))
b1=$((($(pango_h "$(${weather} 1)") + 110) * 3 / 2))
# Agenda event bars + a faint band behind every other event. Events are runs of lines carrying the
# (invisible) ▍ marker; each run is located by measuring the label prefix that ends at it with pango.
stripes=() bars=()
for d in 0 1; do
  mapfile -t lines < <(${weather} "$d")
  block=0 start=-1 x=$((80 + d * 810))
  for ((k = 0; k <= ${#lines[@]}; k++)); do
    if [[ $k -lt ${#lines[@]} && ${lines[k]} == *▍* ]]; then
      ((start < 0)) && start=$k
    elif ((start >= 0)); then
      top=$((80 + $(pango_h "$(printf '%s\n' "${lines[@]:0:start}")")))
      bot=$((80 + $(pango_h "$(printf '%s\n' "${lines[@]:0:k}")")))
      color=$(grep -o "foreground='#[0-9a-f]*' alpha='1'" <<<"${lines[start]}" | cut -d"'" -f2)
      bars+=(-fill "$color" -draw "rectangle $((x * 3 / 2)),$((top * 3 / 2)) $(((x + 5) * 3 / 2)),$((bot * 3 / 2))")
      ((block % 2 == 1)) && stripes+=(-draw "roundrectangle $(((x - 16) * 3 / 2)),$(((top - 4) * 3 / 2)) $(((x + 716) * 3 / 2)),$(((bot + 4) * 3 / 2)) 15,15")
      block=$((block + 1)) start=-1
    fi
  done
done

# the graph sits in the 6 blank rows under the icon + description row
gtop=$((80 + $(pango_h "$(${weather} 0 | sed -n 1,2p)") + 10))

# Rain area (0-100%, gridlines at 50/100) + temperature line per day; temperature shares one scale
# across both days (the high/low numbers sit in the weather row above).
graphs=()
if [[ -f $dir/wttr.json ]]; then
  mapfile -t graphs < <(jq -r --argjson top "$gtop" '
    def S: . * 1.5 | floor;
    [.weather[0,1].hourly | map({h: ((.time | tonumber) / 100), t: (.tempF | tonumber), r: (.chanceofrain | tonumber)})]
    # 3-hourly samples stop at 9pm: run each day to the next midnight (today via the first sample of tomorrow)
    | [(.[0] + [.[1][0] | .h = 24]), (.[1] + [.[1][-1] | .h = 24])] as $d
    | ([$d[][] .t] | min - 2) as $lo | ([$d[][] .t] | max + 2) as $hi
    | ($top + 32) as $y0 | 120 as $H
    | range(0; 2) as $i
    | (80 + $i * 810) as $x0
    | def X(h): ($x0 + h / 24 * 700) | S;
      def Y(f): ($y0 + $H - f * $H) | S;
      def T(t): Y((t - $lo) / ($hi - $lo));
      ($d[$i] | map("\(X(.h)),\(Y(.r / 100))") | join(" ")) as $rain
    | ($d[$i] | map("\(X(.h)),\(T(.t))") | join(" ")) as $temp
    | "-stroke", "rgba(242,238,251,0.18)", "-strokewidth", "2", "-fill", "none",
      "-draw", "line \(X(0)),\(Y(1)) \(X(24)),\(Y(1))", "-draw", "line \(X(0)),\(Y(0.5)) \(X(24)),\(Y(0.5))",
      "-fill", "rgba(122,162,247,0.30)", "-stroke", "#7aa2f7", "-strokewidth", "3",
      "-draw", "polygon \(X(0)),\(Y(0)) \($rain) \(X(24)),\(Y(0))",
      "-fill", "none", "-stroke", "#e0af68", "-strokewidth", "4.5", "-draw", "polyline \($temp)",
      "-stroke", "none", "-fill", "rgba(242,238,251,0.75)", "-pointsize", "30",
      (["6:6a", "12:12p", "18:6p", "24:12a"][] | split(":") | "-annotate", "+\(X(.[0] | tonumber) - (if .[0] == "24" then 44 else 18 end))+\(Y(0) + 36)", .[1])
  ' "$dir/wttr.json")
fi

# ponytail: rects hardcoded for 2560x1440 (input-field 512x72 at bottom-right -50,110; info columns 700+110+700 at 80,80 in 760px cards with 50px gap/margins), scaled x1.5 to the 3840x2160 image
cards=(-draw "roundrectangle 75,75 1215,$b0 36,36" -draw "roundrectangle 1290,75 2430,$b1 36,36")
magick -respect-parentheses "$dir/potd.jpg" -resize '3840x2160^' -gravity center -extent 3840x2160 +gravity \
  \( +clone -blur 0x25 -fill 'rgba(0,0,0,0.25)' -draw 'rectangle 0,0 3840,2160' \
  \( -size 3840x2160 xc:black -fill white -draw 'roundrectangle 2997,1887 3765,1995 22,22' "${cards[@]}" \) \
  -alpha off -compose CopyOpacity -composite \) -compose over -composite \
  -fill 'rgba(26,23,38,0.55)' "${cards[@]}" \
  -fill 'rgba(242,238,251,0.11)' "${stripes[@]}" \
  "${bars[@]}" \
  \( -size 3840x2160 -define gradient:angle=45 gradient:'rgba(187,154,247,0.93)-rgba(157,124,216,0.93)' \
  \( -size 3840x2160 xc:black -fill none -stroke white -strokewidth 4.5 "${cards[@]}" \) \
  -alpha off -compose CopyOpacity -composite \) -compose over -composite \
  -font "$(fc-match -f '%{file}' Inter)" -pointsize 30 "${graphs[@]}" \
  "$dir/potd-lock.tmp.jpg"
# atomic swap: hyprlock reloads this path on a timer
mv "$dir/potd-lock.tmp.jpg" "$dir/potd-lock.jpg"
