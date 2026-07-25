#!/usr/bin/env nu

# sb-check-tiling — ACCEPTANCE TEST for the bar's tiling invariant.
#
# Walks every on-screen sketchybar item, drops the ones fully nested inside a
# wider sibling (cluster glyphs like volume_icon sit INSIDE the volume label's
# footprint), sorts the survivors left→right, and ERRORS if any two adjacent
# top-level footprints gap or overlap by >= 1.5px. A passing run means the bar
# tiles with no dead zones and no overlaps — smooth hover everywhere.
#
# Run with:  nu modules/home-darwin/sketchybar/sb-check-tiling.nu
# (or, once symlinked:  nu ~/.config/sketchybar/sb-check-tiling.nu)

# Threshold for treating rects as "nested" (a cluster glyph inside its label).
const TOL = 1.5
# Overlaps are always bugs → fail on any overlap larger than sub-pixel.
const OVERLAP_TOL = 0.5
# Gaps are only dead zones once they reach this; sub-pixel gaps are fine.
const GAP_TOL = 1.5

def rect-of [name: string] {
  let q = do -i { ^sketchybar --query $name } | complete
  if $q.exit_code != 0 { return null }
  # Query output may carry a leading warning line; keep only from the first `{`.
  let raw = $q.stdout | str trim
  let json = $raw | str substring (($raw | str index-of "{"))..
  let d = $json | from json
  # Only items that are actually drawing on screen count.
  if ($d.geometry?.drawing? | default "on") == "off" { return null }
  let br = $d.bounding_rects? | default {}
  # Pick the first display that has a rect.
  let disps = $br | columns
  if ($disps | is-empty) { return null }
  let r = $br | get ($disps | first)
  let x = $r.origin.0 | into float
  let w = $r.size.0 | into float
  if $w <= 0 { return null }
  # Side (left/center/right): items on different sides are separate groups with
  # an intentional gap between them (the empty bar centre), so tiling is only
  # checked WITHIN a side.
  {
    name: $name
    side: ($d.geometry?.position? | default "left")
    l: $x
    r: ($x + $w)
  }
}

def main [] {
  let items = (
    ^sketchybar --query bar
    | str trim
    | str substring (((^sketchybar --query bar | str trim) | str index-of "{"))..
  ) | from json | get items
  let rects = $items | each {|n| rect-of $n } | compact

  # Drop any rect fully nested inside a strictly-wider sibling (cluster glyph).
  let top = ($rects | where {|a|
    not ($rects | any {|b|
      $b.name != $a.name and $b.l <= ($a.l + $TOL) and $b.r >= ($a.r - $TOL) and (($b.r - $b.l) > ($a.r - $a.l))
    })
  })

  mut bad = 0
  for side in ($top | get side | uniq) {
    let sorted = $top | where side == $side | sort-by l
    if ($sorted | length) < 2 { continue }
    for i in 0..(($sorted | length) - 2) {
      let cur = $sorted | get $i
      let nxt = $sorted | get ($i + 1)
      let gap = ($nxt.l - $cur.r)
      # Asymmetric: an OVERLAP is always a bug (hover ambiguity, visible
      # background bleed), so fail on any overlap > 0.5px. A GAP is only a dead
      # zone once it's >= 1.5px; sub-pixel gaps are fine.
      let overlap = ($gap < ($OVERLAP_TOL * -1))
      let bigGap = ($gap >= $GAP_TOL)
      if $overlap or $bigGap {
        let kind = if $gap < 0 { $"OVERLAP (($gap * -1 | math round)px)" } else { $"GAP (($gap | math round)px)" }
        print $"($cur.name) R=($cur.r) | ($nxt.name) L=($nxt.l) -> ($kind)"
        $bad = $bad + 1
      }
    }
  }

  if $bad > 0 {
    print $"FAIL: ($bad) adjacent pair\(s\) overlap > ($OVERLAP_TOL)px or gap >= ($GAP_TOL)px"
    exit 1
  } else {
    print $"OK: all adjacent footprints abut -- overlap <= ($OVERLAP_TOL)px, gap < ($GAP_TOL)px"
    for r in ($top | sort-by l) { print $"  ($r.side) ($r.name): ($r.l) .. ($r.r)" }
  }
}
