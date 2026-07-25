#!/usr/bin/env nu --stdin

# The volume_change event supplies a $INFO variable with the new volume percent.

# Label-box width per digit count — one source of truth for the tween loop and
# the initial set. (See the item_props comment in main for what the numbers are.)
def vol-width [v: int] {
  if $v >= 100 { 70 } else if $v >= 10 { 61 } else { 52 }
}

# Speaker icon for a volume level, as a PNG rendered by sketchybar-icons — the
# same mechanism (symbols, cache path, point size) volume_icon.nu used before we
# moved it here, so the files are shared. Driven from the tween so the icon fills
# through its states — muted → no waves → 1 → 2 → 3 — in step with the counting
# number. PNGs are cached by path, so after each symbol's first render this is a
# cheap path lookup, fine to call per frame.
const VOL_CACHE_DIR = "~/.cache/sketchybar" | path expand
const VOL_POINT_SIZE = 12
# Centre the small speaker glyph in a MIN_WIDTH canvas so it sits centred in the
# cluster's icon.width (= sb-cluster volume icon_w = 24), like control_center
# does. Without this the tiny glyph left-aligned in the 24px box. In the cache
# filename so stale (uncentred) PNGs bust.
const VOL_MIN_WIDTH = 24

def volume-symbol [pct: int] {
  if $pct <= 0 { "speaker.slash.fill" } else if $pct <= 24 { "speaker.fill" } else if $pct <= 49 { "speaker.wave.1.fill" } else if $pct <= 74 { "speaker.wave.2.fill" } else { "speaker.wave.3.fill" }
}

def vol-icon-image [v: int] {
  let sym = (volume-symbol $v)
  let out = $"($VOL_CACHE_DIR)/volume-($sym)-($VOL_POINT_SIZE)-w($VOL_MIN_WIDTH).png"
  if not ($out | path exists) {
    let w = "0xffffffff"
    sketchybar-icons symbol --symbol $sym --point-size $VOL_POINT_SIZE --scale 2 --min-width $VOL_MIN_WIDTH --palette $"($w),($w),($w),($w)" --out $out
  }
  $out
}

# Paint one frame: the number + its box width AND the speaker icon for that
# level, in one sketchybar call so icon and number stay in lockstep. label.width
# animates (tanh 5) so a digit-count crossing (9→10, 99→100) glides the icon
# instead of snapping; the label text and icon image are instant. Records the
# shown value so the next event tweens from what's on screen, not a stale target.
def set-vol [v: int] {
  sketchybar --animate tanh 5 --set volume $"label=($v)%" $"label.width=(vol-width $v)" --set volume_icon $"icon.background.image=(vol-icon-image $v)"
  $v | save -f /tmp/sketchybar_volume_cur
}

def main [] {

  # Geometry (the 24px icon zone/pull, label.width, align, paddings) is owned by
  # the `sb-cluster volume` primitive in sketchybarrc.nu — this plugin sets only
  # CONTENT: the number and speaker icon. label.width is re-set per digit-count
  # by set-vol's animated tween (a dynamic value, not static geometry).
  match $env.SENDER {
    "volume_change" => {

      # Tween the displayed number toward the new volume so e.g. 56→63 ticks up
      # instead of snapping. sketchybar can animate numeric *properties* (we use
      # that for label.width in set-vol, so the icon glides at 9→10 / 99→100) but
      # NOT label text — so we step the number ourselves, one frame at a time.
      #
      # A per-event random token supersedes an in-flight tween: every frame bails
      # if the token has moved on (a newer volume_change wrote its own), so only
      # the latest change runs to its end and its final value is always correct.
      let target = $env.INFO | into int
      let gen = (random int 0..999999999)
      $gen | save -f /tmp/sketchybar_volume_gen
      let current = (
        try {
          open --raw /tmp/sketchybar_volume_cur | str trim | into int
        } catch { $target }
      )

      if $current == $target {
        set-vol $target
      } else {
        let delta = ($target - $current)
        let mag = $delta | math abs
        # One integer per frame for small changes (real "counting"); cap the
        # frame count so big jumps still finish quickly. Tuning knobs: this cap
        # (max frames) and the sleep below (per-frame time) — lower either to
        # make the count snappier.
        let steps = (if $mag > 10 { 10 } else { $mag })
        for i in 1..$steps {
          if (open --raw /tmp/sketchybar_volume_gen | str trim | into int) != $gen { return }
          let v = $current + $delta * $i / $steps | math round | into int
          set-vol $v
          sleep 5ms
        }
      }
    }
    "forced" => {
      # Seed the number + icon from the current volume on (re)load, so the
      # readout is right before the first volume_change. Mute shows as 0.
      let muted = (
        (osascript -e 'output muted of (get volume settings)' | str trim) == "true"
      )
      let cur = if $muted { 0 } else {
        (
        try {
          osascript -e 'output volume of (get volume settings)'
          | str trim
          | into int
        } catch { 0 }
      )
      }
      set-vol $cur
    }
  }
}
