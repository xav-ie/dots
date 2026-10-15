# wttr.in weatherCode → Nerd Font (nf-md) glyph + color, matching
# the symbolic-icon buckets the notification-center Weather card uses.
let glyph = {|cp color|
  $"<span font_family='CaskaydiaCove Nerd Font Propo' foreground='($color)'>(char -u $cp)</span>"
}
let icon_of = {|code|
  if $code == 113 {
    {cp: "f0599" color: "#e0af68"} # weather_sunny
  } else if $code == 116 {
    {cp: "f0595" color: "#e0af68"} # weather_partly_cloudy
  } else if $code in [119 122] {
    {cp: "f0590" color: "#a9b1d6"} # weather_cloudy
  } else if $code in [143 248 260] {
    {cp: "f0591" color: "#a9b1d6"} # weather_fog
  } else if $code in [200 386 389 392 395] {
    {cp: "f067e" color: "#bb9af7"} # weather_lightning_rainy
  } else if $code in [
    179
    227
    230
    323
    326
    329
    332
    335
    338
    368
    371
  ] {
    {cp: "f0598" color: "#c0caf5"} # weather_snowy
  } else if $code >= 176 {
    {cp: "f0597" color: "#7aa2f7"} # weather_rainy
  } else { {cp: "f0595" color: "#e0af68"} }
}

let esc = {|s| $s | str replace -a '&' '&amp;' | str replace -a '<' '&lt;' | str replace -a '>' '&gt;' }
let cache = $env.XDG_CACHE_HOME? | default $"($env.HOME)/.cache" | path join hyprlock

# Today and Tomorrow are separate labels, so both read one cached forecast;
# the lock image draws its rain/temperature graphs from the same file.
let forecast = {||
  let file = $cache | path join wttr.json
  if ($file | path exists) and ((date now) - (ls $file | get 0.modified) < 10min) {
    return (open $file)
  }
  let conf = (
    [
      ($env.XDG_CONFIG_HOME? | default $"($env.HOME)/.config")
      hyprlock-weather
      config.toml
    ]
    | path join
  )
  let loc = (
    if ($conf | path exists) {
      open $conf | get -o location | default ""
    } else { "" }
  )
  let j = http get --max-time 10sec $"https://wttr.in/($loc)?format=j1" | from json
  mkdir $cache
  $j | to json -r | save -f $file
  $j
}

let weather = {|day|
  try {
    let j = do $forecast
    let d = $j.weather | get $day
    # wttr.in sometimes truncates the current day's hourly array, so guard
    # the midday lookup.
    let hourly = $d.hourly | default []
    # Today uses the live current condition; tomorrow the ~midday hourly
    # entry (3-hourly → index 4 ≈ 12:00).
    let src = if $day == 0 { $j.current_condition.0 } else { $hourly | get -o 4 | default ($hourly | last) }
    {
      icon: (do $icon_of ($src.weatherCode | into int))
      hi: $d.maxtempF
      lo: $d.mintempF
      # current_condition sentence-cases the description but the hourly
      # feed Title-Cases it; normalise so today and tomorrow agree.
      desc: ($src.weatherDesc.0.value | str trim | str lowercase | str capitalize)
    }
  } catch {
    # Network down (common right after wake), rate-limit, or bad payload.
    null
  }
}

# Agenda titles are 22pt Inter (~14-16px/char), so 42 chars wrap safely in the 700px card column.
let width = 42
let wrap = {|t n|
  let words = $t | split row " " | where {|w| $w != "" }
  let lines = $words | reduce -f [""] {|w, acc|
    let last = $acc | last
    if $last == "" { $acc | drop | append ($w | str substring -g 0..<$n) } else if (($last | str length -g) + 1 + ($w | str length -g)) <= $n { $acc | drop | append $"($last) ($w)" } else { $acc | append ($w | str substring -g 0..<$n) }
  }
  if ($lines | length) > 2 {
    let second = $lines | get 1
    [($lines | get 0) ((if ($second | str length -g) >= $n { $second | str substring -g 0..<($n - 1) } else { $second }) + "…")]
  } else { $lines }
}
let agenda = {|events|
  if $events == null { return [] }
  if ($events | is-empty) { return ["<span font_family='${sansFont}' foreground='#a9b1d6'>nothing scheduled</span>"] }
  $events | each {|e|
    # invisible: keeps the indent and tells the lock image which colour to bake the bar in
    let bar = $"<span foreground='(if $e.acct == 'work' { '#7aa2f7' } else { '#bb9af7' })' alpha='1'>▍</span>"
    # mono line padded to the 40 cells after the bar, so the duration sits flush right
    let dur = $e.dur? | default ""
    let gap = 40 - ($e.time | str length -g) - ($dur | str length -g)
    [$"($bar)<span foreground='#f0cfa0'>($e.time)('' | fill -w $gap)<span foreground='#cdb4fb'>($dur)</span></span>"]
    | append $"<span line_height='0.2'>($bar)</span>"
    | append (do $wrap $e.title $width | each {|l| $"($bar)<span font_family='${sansFont}'>(do $esc $l)</span>" })
  } | each {|lines| $lines | str join "\n" } | str join "\n<span size='68%'> </span>\n"
  | lines
}

# --hilo: the day's high/low alone, for a right-aligned label over the card; an invisible header and
# icon give it the weather row's exact line metrics so it shares that baseline.
def main [day: int = 0, --hilo] {
  let x = do $weather $day
  if $hilo {
    if $x == null { return }
    print $"(char -u '200b')<span font='${sansFont}' size='150%' alpha='1'>Today</span>\n<span size='150%' alpha='1'>(do $glyph $x.icon.cp $x.icon.color)</span><span font_family='${sansFont}' size='75%' foreground='#f0cfa0'>($x.hi)° <span alpha='55%'>/</span> ($x.lo)°</span>"
    return
  }
  # Headers in Inter (matching the clock label beside them); data in mono.
  # The leading zero-width space is load-bearing: hyprgraphics inserts a
  # scale=1 attr over [0, END] after parsing markup, which clobbers any
  # markup scale starting at index 0 — so a header's size='150%' is lost
  # unless something unscaled occupies index 0. Today's header is invisible:
  # the live clock label sits on it.
  let head = $"(char -u '200b')<span font='${sansFont}' size='150%'(if $day == 0 { " alpha='1'" } else { "" })>(if $day == 0 { "Today" } else { "Tomorrow" })</span>"
  # rain chance lives in the graph the lock image draws below
  let row = if $x == null { "unavailable" } else {
    $"<span size='150%'>(do $glyph $x.icon.cp $x.icon.color)</span> <span font_family='${sansFont}' size='90%'>(do $esc $x.desc)</span>"
  }
  let small = {|m| $"<span font='CaskaydiaCove Nerd Font Mono 22'>($m)</span>" }
  # blank rows the lock image draws the rain/temperature graph into (6 × 35px)
  let graph = 1..6 | each { do $small " " }
  let events = try { ^${agenda} | from json | get -o $day } catch { null }
  [$head $row]
  | append $graph
  | append (do $agenda $events | each {|l| $"<span font='CaskaydiaCove Nerd Font Mono 22'>($l)</span>" })
  | str join "\n"
  | print
}
