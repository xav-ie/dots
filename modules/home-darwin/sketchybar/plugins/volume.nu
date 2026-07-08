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
const VOL_CACHE_DIR = ("~/.cache/sketchybar" | path expand)
const VOL_POINT_SIZE = 12

def volume-symbol [pct: int] {
  if $pct <= 0 { "speaker.slash.fill" } else if $pct <= 24 { "speaker.fill" } else if $pct <= 49 { "speaker.wave.1.fill" } else if $pct <= 74 { "speaker.wave.2.fill" } else { "speaker.wave.3.fill" }
}

def vol-icon-image [v: int] {
  let sym = (volume-symbol $v)
  let out = $"($VOL_CACHE_DIR)/volume-($sym)-($VOL_POINT_SIZE).png"
  if not ($out | path exists) {
    let w = "0xffffffff"
    sketchybar-icons symbol --symbol $sym --point-size $VOL_POINT_SIZE --scale 2 --palette $"($w),($w),($w),($w)" --out $out
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
  let item_props = [
    "click_script=$HOME/.config/sketchybar/open_volume_control.scpt"
    "icon.padding_left=0"
    "icon.padding_right=0"
    # Reserve a 28px zone on the label's left for the speaker icon, exactly like
    # battery.nu (label.padding_left=40 / padding_left=-40). label.padding_left
    # extends the label's *background* — the hover highlight the daemon paints —
    # leftward over the icon, and the matching negative padding_left pulls this
    # item back over the separate `volume_icon` so its glyph sits inside that
    # zone. Result: hovering the icon or the number lights one box around both.
    "label.padding_left=28"
    "label.padding_right=4"
    # label.width (set per-value in volume_change) is the *total* label region —
    # the 28px icon zone + the number + right pad — so it also sizes the hover
    # box. It's a fixed value per digit-count, and right align pins the % to the
    # battery side. Stable right align relies on our sketchybar fork: stock
    # sketchybar positions right/center text by ink width, so equal-*advance*
    # tabular values ("25%" vs "31%") wobbled inside the box; the fork aligns by
    # the typographic advance width (see the `sketchybar` override in
    # overlays/default.nix), so same-digit values render identically.
    # This default is overridden immediately on the first volume_change.
    "label.width=61"
    "label.align=right"
    "padding_left=-28"
    # Small right pad so the volume button sits just clear of the battery button.
    "padding_right=3"
  ];

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
      let target = ($env.INFO | into int)
      let gen = (random int 0..999999999)
      $gen | save -f /tmp/sketchybar_volume_gen
      let current = (try { open --raw /tmp/sketchybar_volume_cur | str trim | into int } catch { $target })

      if $current == $target {
        set-vol $target
      } else {
        let delta = ($target - $current)
        let mag = ($delta | math abs)
        # One integer per frame for small changes (real "counting"); cap the
        # frame count so big jumps still finish quickly. Tuning knobs: this cap
        # (max frames) and the sleep below (per-frame time) — lower either to
        # make the count snappier.
        let steps = (if $mag > 10 { 10 } else { $mag })
        for i in 1..$steps {
          if (open --raw /tmp/sketchybar_volume_gen | str trim | into int) != $gen { return }
          let v = ($current + (($delta * $i / $steps) | math round | into int))
          set-vol $v
          sleep 5ms
        }
      }
    }
    "forced" => {
      sketchybar --set $"($env.NAME)" ...$item_props
      # Seed the number + icon from the current volume on (re)load, so the
      # readout is right before the first volume_change. Mute shows as 0.
      let muted = ((osascript -e 'output muted of (get volume settings)' | str trim) == "true")
      let cur = if $muted { 0 } else { (try { osascript -e 'output volume of (get volume settings)' | str trim | into int } catch { 0 }) }
      set-vol $cur
    }
  }
}
