#!/usr/bin/env nu --stdin

# The volume_change event supplies a $INFO variable in which the current volume
# percentage is passed to the script.
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
    # The label.width (set per-value in volume_change) is the *total* label
    # region — the 28px icon zone + the number + right pad — so it's also the
    # width of the hover box. Fixing it per digit-count keeps the readout stable:
    #   * A fixed width stops the item resizing by rendered *ink* between values
    #     (which used to jitter the icon ±1px).
    #   * Stable right align relies on our sketchybar fork: stock sketchybar
    #     positions right/center text by ink width, so equal-*advance* tabular
    #     values ("25%" vs "31%") still wobbled inside the box. The fork aligns
    #     by the typographic advance width (see the `sketchybar` override in
    #     overlays/default.nix), so same-digit values render identically.
    # This default is overridden immediately on the first volume_change.
    "label.width=61"
    "label.align=right"
    "padding_left=-28"
    # Small right pad so the volume button sits just clear of the battery button.
    "padding_right=3"
  ];

  match $env.SENDER {
    "volume_change" => {
      # Size the box to the digit count: 28px icon zone + tabular advance of N
      # digits + "%" + paddings, one tabular digit (~9px) per step. The % stays
      # pinned to the battery edge (right edge is anchored) at every value; only
      # the box's left edge — icon included — steps left when the value gains a
      # digit (9→10, 99→100). Too small and right-align would push the number's
      # left edge back under the icon (clips, worst at 1 digit).
      let v = ($env.INFO | into int)
      let width = if $v >= 100 { 70 } else if $v >= 10 { 61 } else { 52 }
      # Animate label.width so a digit-count crossing (9→10, 99→100) glides the
      # icon ~9px instead of snapping. `tanh` is sketchybar's symmetric S-curve
      # (ease-in-out: slow→fast→slow); `sin`/`circ` are ease-out, `quadratic`/
      # `exp` ease-in. 6 frames ≈ 0.1s. The label string updates instantly (text
      # isn't animatable); within a digit-count the target width is unchanged, so
      # sketchybar treats it as a no-op — no lag on normal volume steps.
      sketchybar --animate tanh 6 --set $"($env.NAME)" $"label=($env.INFO)%" $"label.width=($width)"
    }
    "forced" => {
      sketchybar --set $"($env.NAME)" ...$item_props
    }
  }
}
