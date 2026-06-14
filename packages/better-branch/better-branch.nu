def spinner [] {
  ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
  | each { |x|
    print -ne $"(ansi green)($x)(ansi reset) Fetching remote data...\r"
    sleep 35ms
  }
  return
}

# [ahead, behind] of `branch` relative to `base`.
def rev-counts [base: string, branch: string] {
  let ahead = (
    git rev-list --count $"($base)..($branch)" | complete | $in.stdout | into int
  )
  let behind = (
    git rev-list --count $"($branch)..($base)" | complete | $in.stdout | into int
  )
  [$ahead, $behind]
}

# Render [ahead, behind] as a single "↑a ↓b" cell, padding each field to the
# given widths (computed from the data) so columns align, or `dash` when null.
# [ahead-digits, behind-digits] needed to print a list of [ahead, behind] pairs.
def col-widths [pairs: list] {
  let wa = ($pairs | each { |c| $c.0 | into string | str length } | append 1 | math max)
  let wb = ($pairs | each { |c| $c.1 | into string | str length } | append 1 | math max)
  [$wa, $wb]
}

# --- OKLab color space (perceptually uniform) for the heat-map gradient ---
# Gradient endpoints are interpolated in OKLab so the transition is even to the
# eye and stays saturated through the middle, unlike a linear-sRGB blend.

def srgb-to-linear [c: float] {
  if $c <= 0.04045 { $c / 12.92 } else { (($c + 0.055) / 1.055) ** 2.4 }
}

def linear-to-byte [c: float] {
  let s = if $c <= 0.0031308 { 12.92 * $c } else { 1.055 * ($c ** (1 / 2.4)) - 0.055 }
  let v = (($s * 255) | math round)
  [([$v 255] | math min) 0] | math max
}

# sRGB [r g b] (0–255) → OKLab [L a b].
def rgb-to-oklab [rgb: list] {
  let r = (srgb-to-linear ($rgb.0 / 255))
  let g = (srgb-to-linear ($rgb.1 / 255))
  let b = (srgb-to-linear ($rgb.2 / 255))
  let l = ((0.4122214708 * $r + 0.5363325363 * $g + 0.0514459929 * $b) ** (1 / 3))
  let m = ((0.2119034982 * $r + 0.6806995451 * $g + 0.1073969566 * $b) ** (1 / 3))
  let s = ((0.0883024619 * $r + 0.2817188376 * $g + 0.6299787005 * $b) ** (1 / 3))
  [
    (0.2104542553 * $l + 0.7936177850 * $m - 0.0040720468 * $s),
    (1.9779984951 * $l - 2.4285922050 * $m + 0.4505937099 * $s),
    (0.0259040371 * $l + 0.7827717662 * $m - 0.8086757660 * $s)
  ]
}

# OKLab [L a b] → sRGB [r g b] (0–255).
def oklab-to-rgb [lab: list] {
  let l = (($lab.0 + 0.3963377774 * $lab.1 + 0.2158037573 * $lab.2) ** 3)
  let m = (($lab.0 - 0.1055613458 * $lab.1 - 0.0638541728 * $lab.2) ** 3)
  let s = (($lab.0 - 0.0894841775 * $lab.1 - 1.2914855480 * $lab.2) ** 3)
  [
    (linear-to-byte (4.0767416621 * $l - 3.3077115913 * $m + 0.2309699292 * $s)),
    (linear-to-byte (-1.2684380046 * $l + 2.6097574011 * $m - 0.3413193965 * $s)),
    (linear-to-byte (-0.0041960863 * $l - 0.7034186147 * $m + 1.7076147010 * $s))
  ]
}

# Color `text` by its commit age relative to the set: oldest → lab0 (purple),
# newest → lab1 (cyan), interpolated in OKLab. Smooth truecolor (~256 steps).
def heat-time [text: string, ts: int, min_ts: int, span: int, lab0: list, lab1: list] {
  let t = if $span <= 0 { 1.0 } else { ($ts - $min_ts) / $span }
  let lab = [
    ($lab0.0 + ($lab1.0 - $lab0.0) * $t),
    ($lab0.1 + ($lab1.1 - $lab0.1) * $t),
    ($lab0.2 + ($lab1.2 - $lab0.2) * $t)
  ]
  let rgb = (oklab-to-rgb $lab)
  $"(ansi -e $'38;2;($rgb.0);($rgb.1);($rgb.2)m')($text)(ansi reset)"
}

def fmt-counts [counts: any, dash: string, wa: int, wb: int] {
  if $counts == null {
    $dash
  } else {
    # Pad the numbers (ASCII) and prepend the arrow; padding the arrowed string
    # would count the 3-byte ↑/↓ via `str length` and over-pad.
    let ahead = ($counts.0 | into string | fill --alignment left --width $wa)
    let behind = ($counts.1 | into string | fill --alignment left --width $wb)
    $"(ansi green)↑($ahead)(ansi reset) (ansi red)↓($behind)(ansi reset)"
  }
}

# The integration branch to measure against: the remote HEAD's target (e.g.
# `main`/`master`), falling back to a local main/master when origin/HEAD is unset.
def default-branch [] {
  let head = (git symbolic-ref --quiet refs/remotes/origin/HEAD | complete)
  if $head.exit_code == 0 {
    return ($head.stdout | str trim | str replace "refs/remotes/origin/" "")
  }
  for candidate in [main master] {
    let exists = (
      git show-ref --verify --quiet $"refs/heads/($candidate)" | complete | $in.exit_code == 0
    )
    if $exists { return $candidate }
  }
  "main"
}

def main [] {
  let cpus = (sys cpu | length)
  let fetch_job_id = job spawn { git fetch --quiet --all -j $cpus }
  while (job list | where id == $fetch_job_id | length) == 1 {
    spinner
  }

  let base = (default-branch)
  let current = (git branch --show-current | str trim)

  # Get both local and remote branches
  let local_branches = (git for-each-ref --count=20 --sort=-committerdate
    --format="%(refname:short)|%(upstream:short)|%(committerdate:relative)|%(committerdate:unix)|local" refs/heads/
    | lines
    | par-each { |line| $line | split row "|" }
    | par-each { |cols| {
      branch: ($cols | get 0),
      upstream: ($cols | get 1),
      time: ($cols | get 2),
      timestamp: ($cols | get 3 | into int),
      type: ($cols | get 4)
    }})

  # Remote branches already tracked by a local branch just duplicate info the
  # local row's "vs upstream" already shows, so only keep remote-only ones.
  let local_upstreams = ($local_branches | get upstream | where ($it | is-not-empty))

  let remote_branches = (git for-each-ref --count=20 --sort=-committerdate
    --format="%(refname:short)|%(symref)|%(committerdate:relative)|%(committerdate:unix)|remote" refs/remotes/
    | lines
    | par-each { |line| $line | split row "|" }
    # Drop the remote HEAD symref (e.g. `origin` → refs/remotes/origin/HEAD);
    # symbolic refs carry a non-empty %(symref).
    | where ($it | get 1 | is-empty)
    | par-each { |cols| {
      branch: ($cols | get 0),
      upstream: "",
      time: ($cols | get 2),
      timestamp: ($cols | get 3 | into int),
      type: ($cols | get 4)
    }}
    | where branch not-in $local_upstreams)

  let all_branches = ($local_branches ++ $remote_branches)

  let dim_dash = $"(ansi default_dimmed)-(ansi reset)"

  # Pass 1: gather raw [ahead, behind] counts (null = no comparison / dash).
  let rows = $all_branches | par-each { |it|
    if $it.type == "remote" {
      {
        label: $"(ansi cyan)($it.branch)(ansi reset)",
        main: null,
        upstream: null,
        time: $it.time,
        timestamp: $it.timestamp
      }
    } else {
      # vs <base>: how this branch sits against the integration branch.
      let main_counts = (rev-counts $base $it.branch)
      # vs upstream: drift from this branch's own origin/<branch>, or null
      # when it has no upstream / the remote ref is gone.
      let upstream_counts = if ($it.upstream | is-empty) {
        null
      } else {
        let remote_exists = (
          git show-ref --verify --quiet $"refs/remotes/($it.upstream)"
          | complete
          | $in.exit_code == 0
        )
        if $remote_exists { (rev-counts $it.upstream $it.branch) } else { null }
      }
      # Mark the checked-out branch with a trailing bold green `●`.
      let label = if $it.branch == $current {
        $"(ansi green_bold)($it.branch) ●(ansi reset)"
      } else {
        $"(ansi blue)($it.branch)(ansi reset)"
      }
      { label: $label, main: $main_counts, upstream: $upstream_counts, time: $it.time, timestamp: $it.timestamp }
    }
  }

  # One shared field width across both count columns: keeps them equal-width so
  # nushell's centered headers line up identically (no per-column parity drift).
  let cw = (col-widths ($rows | each { |r| [$r.main, $r.upstream] } | flatten | where ($it != null)))

  # Relative-age heat map for the Last Commit column: oldest purple → newest
  # cyan, interpolated in OKLab. Endpoints converted once.
  let min_ts = ($rows | get timestamp | math min)
  let max_ts = ($rows | get timestamp | math max)
  let span = ($max_ts - $min_ts)
  let heat0 = (rgb-to-oklab [37 99 235])   # blue (oldest)
  let heat1 = (rgb-to-oklab [46 204 64])   # green (newest)

  # Pass 2: render with the per-column widths.
  let branch_data = $rows | each { |r|
    {
      "branch": $r.label,
      ($base): (fmt-counts $r.main $dim_dash $cw.0 $cw.1),
      "upstream": (fmt-counts $r.upstream $dim_dash $cw.0 $cw.1),
      "last-commited": (heat-time $r.time $r.timestamp $min_ts $span $heat0 $heat1),
      "timestamp": $r.timestamp
    }
  }

  # Sort by timestamp (newest first) and remove temporary field
  $branch_data
  | sort-by timestamp
  | reject timestamp
  | table -t compact
}
