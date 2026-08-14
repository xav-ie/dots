#!/usr/bin/env -S nu --stdin

def fmt-tokens [n: int] {

  # 999_950 not 1_000_000: rounding to 1dp above that yields "1000.0k"
  if $n >= 999_950 {
    $"($n / 1_000_000 | math round --precision 1)M"
  } else if $n >= 1_000 {
    $"($n / 1_000 | math round --precision 1)k"
  } else {
    $"($n)"
  }
  | str replace --regex '\.0([kM])$' '$1' # 1.0M -> 1M
}

# Stable per-string color: the same model or session always gets the same hue, so
# Haiku vs Opus (and one pane vs another) are distinguishable at a glance. Palette is
# 256-color, restricted to shades readable on a dark background.
# 20 entries, not 16: a 16-slot palette collides Sonnet with Haiku, which is exactly
# the distinction this is for. At 20 the current model names all land on separate hues
# — recheck with a one-liner if upstream renames them.
def hash-color [s: string] {
  let palette = [
    39
    45
    51
    69
    75
    81
    105
    111
    117
    141
    147
    153
    171
    177
    183
    189
    203
    209
    215
    221
  ]
  let h = $s | hash md5 | str substring 0..<2 | into int --radix 16
  $palette | get ($h mod ($palette | length))
}

def paint [code: int] {
  let s = $in
  $"(ansi -e $'38;5;($code)m')($s)(ansi reset)"
}

def main [] {
  let input = $in | from json
  # Both optional: context_window is absent until the first turn lands, and
  # session_id only shows up on payloads that carry the session spread.
  # used = input + cache_creation + cache_read, i.e. what occupies the window.
  let used = $input | get -o context_window.total_input_tokens
  let size = $input | get -o context_window.context_window_size
  let session = $input | get -o session_id

  # "Opus 5 (1M context)" -> "Opus 5 (268.6k / 1M)"; upstream's own parenthetical
  # already names the window, so replace it rather than sit beside it.
  # Hash the bare name, so a model keeps its color across window variants.
  let base = $input.model.display_name | str replace --regex ' *\(.*\)$' ''
  let model_display = if $used != null and $size != null {
    # Counts are colored by how full the window is, not by hash — severity is the
    # useful signal here: green well clear, amber past half, red near compaction.
    let pct = $used * 100 / $size
    let counts = $"(fmt-tokens $used) / (fmt-tokens $size)"
    | paint (if $pct >= 80 { 203 } else if $pct >= 50 { 221 } else { 114 })
    $"($base | paint (hash-color $base)) \(($counts)\)"
  } else {
    $base | paint (hash-color $base)
  }
  # prompt-render comes from nu_plugin_prompt — in-process, no subprocess. Its
  # trailing newline is what puts the rest on its own line, so it is left intact
  # and the pieces below are appended with no separator.
  let prompt = prompt-render

  let rest = [
    $model_display
    (
      if $session != null {
        $session | paint (hash-color $session)
      }
    )
  ]
  | compact
  | str join ' '

  print $"($prompt)($rest)"
}
