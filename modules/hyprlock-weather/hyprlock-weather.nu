# wttr.in weatherCode → Nerd Font (nf-weather) glyph codepoint, matching
# the symbolic-icon buckets the notification-center Weather card uses.
let icon_of = {|code|
  if $code == 113 {
    "e30d" # day_sunny
  } else if $code == 116 {
    "e302" # day_cloudy
  } else if $code in [119 122] {
    "e312" # cloudy
  } else if $code in [143 248 260] {
    "e313" # fog
  } else if $code in [200 386 389 392 395] {
    "e31d" # thunderstorm
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
    "e31a" # snow
  } else if $code >= 176 {
    "e319" # showers
  } else { "e302" }
}
try {
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
  let cur = $j.current_condition.0
  # Today uses the live current condition; tomorrow the ~midday hourly
  # entry (3-hourly → index 4 ≈ 12:00). Rain is the day's peak chance.
  let mk = {|d live|
    # wttr.in sometimes truncates the current day's hourly array, so guard
    # the midday lookup; seed the rain max so an empty list can't throw.
    let hourly = $d.hourly | default []
    let src = (
      if $live { $cur } else {
        $hourly | get -o 4 | default ($hourly | last)
      }
    )
    {
      icon: (char -u (do $icon_of ($src.weatherCode | into int)))
      rain: (
        $hourly
        | each {|h| $h.chanceofrain | into int }
        | append 0
        | math max
      )
      hi: $d.maxtempF
      lo: $d.mintempF
      # current_condition sentence-cases the description but the hourly
      # feed Title-Cases it; normalise so today and tomorrow agree.
      desc: (
        $src.weatherDesc.0.value
        | str trim
        | str downcase
        | str capitalize
      )
    }
  }
  let days = [
    (do $mk $j.weather.0 true)
    (do $mk $j.weather.1 false)
  ]
  # Description column fits the wider of the two days, no fixed slack.
  let dw = $days | each {|x| $x.desc | str length } | math max
  # Fixed-width fields keep columns aligned between the two rows while
  # the whole block stays flush-right (text_align=right): every field
  # is right-aligned so the text hugs the edge.
  # The condition glyph is doubled and dropped via a pango <span>.
  let fmt = {|x|
    # Drop the umbrella glyph outside the padded field so it stays in a
    # fixed column hard against the temp; only the digits right-pad.
    let rainf = $"($x.rain)%" | fill -a r -w 4
    let temp = $"($x.hi)°/($x.lo)°" | fill -a r -w 8
    let desc = $x.desc | fill -a r -w $dw
    $"($desc) <span size='200%' rise='-19000'>($x.icon)</span>($temp) (char -u e371)($rainf)"
  }
  # Headers in Inter ExtraLight (matching the clock/date module); data in
  # mono. The leading zero-width space is load-bearing: hyprgraphics
  # inserts a scale=1 attr over [0, END] after parsing markup, which
  # clobbers any markup scale starting at index 0 — so the first header's
  # size='150%' is lost unless something unscaled occupies index 0.
  let head = {|t| $"<span font='${sansFont} ExtraLight' size='150%'>($t)</span>" }
  print $"(char -u '200b')(do $head Today)\n(do $fmt ($days | get 0))\n\n(do $head Tomorrow)\n(do $fmt ($days | get 1))"
} catch {
  # Network down (common right after wake), rate-limit, or bad payload:
  # degrade to a single line instead of a blank region on the lock screen.
  print $"(char -u '200b')<span font='${sansFont} ExtraLight' size='150%'>Weather unavailable</span>"
}
