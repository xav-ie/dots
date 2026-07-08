# Generate a flamegraph of Nix evaluation time
# Usage: nix-flamegraph [flake-output]
# Examples:
#   nix-flamegraph .#darwinConfigurations.nox.system
#   nix-flamegraph .#nixosConfigurations.praesidium.config.system.build.toplevel
def main [
  flake_output?: string  # Flake output to profile (auto-detects based on host)
] {
  let flake_output = $flake_output | default (get-default-flake-output)
  let tmpdir = (mktemp -d -t nix-flamegraph.XXX)
  let profile_file = $"($tmpdir)/nix.profile"
  let readable_profile = $"($tmpdir)/nix-readable.profile"
  let dots_profile = $"($tmpdir)/nix-dots.profile"
  let output_svg = $"($tmpdir)/nix-flamegraph.svg"

  print $"Evaluating ($flake_output) with profiler..."

  # Run nix eval with profiler AND stats (single evaluation)
  let eval_result = (do {
    $env.NIX_SHOW_STATS = "1"
    (^nix eval $flake_output
      --no-eval-cache
      --option eval-profiler flamegraph
      --option eval-profile-file $profile_file)
  } | complete)

  # Parse stats from stderr (JSON format) - skip warning lines before JSON
  let json_start = ($eval_result.stderr | str index-of "{")
  let stats = if $json_start >= 0 {
    try { $eval_result.stderr | str substring $json_start.. | from json } catch { |_| null }
  } else {
    null
  }

  print "Processing profile..."

  # Read profile and find dots source hash
  let profile_content = open $profile_file

  # Find the dots hash by looking for source paths that contain project-specific files
  # Strategy: find sources with darwinConfigurations, nixosConfigurations, or home-manager paths
  let dots_candidates = ($profile_content
    | parse --regex '/nix/store/([a-z0-9]+)-source/(darwinConfigurations|nixosConfigurations|home-manager)/'
    | get capture0
    | uniq)

  let dots_hash = if ($dots_candidates | is-empty) {
    # Fallback: find source with flake.nix that's NOT nixpkgs (doesn't have lib/modules.nix)
    let flake_sources = ($profile_content
      | parse --regex '/nix/store/([a-z0-9]+)-source/flake\.nix'
      | get capture0
      | uniq)
    let nixpkgs_sources = ($profile_content
      | parse --regex '/nix/store/([a-z0-9]+)-source/lib/modules\.nix'
      | get capture0
      | uniq)
    let non_nixpkgs = ($flake_sources | where { |h| not ($nixpkgs_sources | any { |n| $n == $h }) })
    if ($non_nixpkgs | is-empty) { "" } else { $non_nixpkgs | first }
  } else {
    $dots_candidates | first
  }

  print $"Dots source hash: ($dots_hash)"

  # Replace nix store paths with readable names
  let readable_content = ($profile_content
    | str replace --all $"/nix/store/($dots_hash)-source" "[dots]"
    | str replace --all --regex '/nix/store/[a-z0-9]+-source/lib/' "[nixpkgs]/lib/"
    | str replace --all --regex '/nix/store/[a-z0-9]+-source/pkgs/' "[nixpkgs]/pkgs/"
    | str replace --all --regex '/nix/store/[a-z0-9]+-source/nixos/' "[nixpkgs]/nixos/"
    | str replace --all --regex '/nix/store/[a-z0-9]+-source/modules/system/' "[nix-darwin]/modules/system/"
    | str replace --all --regex '/nix/store/[a-z0-9]+-source/modules/nix/' "[nix-darwin]/modules/nix/"
    | str replace --all --regex '/nix/store/[a-z0-9]+-source/modules/environment/' "[nix-darwin]/modules/environment/"
    | str replace --all --regex '/nix/store/[a-z0-9]+-source/modules/launchd/' "[nix-darwin]/modules/launchd/"
    | str replace --all --regex '/nix/store/[a-z0-9]+-source/modules/services/' "[nix-darwin]/modules/services/"
    | str replace --all --regex '/nix/store/[a-z0-9]+-source/nixos/modules/' "[nixos]/modules/"
    | str replace --all --regex '/nix/store/[a-z0-9]+-source/modules/programs/' "[home-manager]/modules/programs/"
    | str replace --all --regex '/nix/store/[a-z0-9]+-source/modules/files\.nix' "[home-manager]/modules/files.nix"
    | str replace --all --regex '/nix/store/[a-z0-9]+-source/modules/' "[modules]/modules/"
    | str replace --all --regex '/nix/store/[a-z0-9]+-source/nix-darwin/' "[home-manager]/nix-darwin/"
    | str replace --all --regex '/nix/store/[a-z0-9]+-source/lib\.nix' "[flake-parts]/lib.nix"
    | str replace --all --regex '/nix/store/[a-z0-9]+-source/eval-config\.nix' "[nix-darwin]/eval-config.nix"
    | str replace --all --regex '/nix/store/[a-z0-9]+-source' "[other]")

  $readable_content | save --force $readable_profile

  # Filter to only stacks that touch user code
  let dots_content = ($readable_content | lines | where { |line| $line | str contains "[dots]" } | str join "\n")
  $dots_content | save --force $dots_profile

  let sample_count = ($dots_content | lines | length)
  print $"Found ($sample_count) samples touching your code"

  print "Generating flamegraph..."

  # Generate flamegraph
  let flamegraph_result = (do { inferno-flamegraph --title "Nix Eval Flamegraph - [dots] in blue" $dots_profile } | complete)
  $flamegraph_result.stdout | save --force $output_svg

  # Highlight [dots] frames in blue (steel blue)
  let svg_content = (open $output_svg
    | str replace --all --regex '(<title>\[dots\]/[^<]+</title><rect [^>]*fill=")rgb\([^)]+\)"' '${1}rgb(70,130,180)"')
  $svg_content | save --force $output_svg

  try {
    open-file $output_svg
    print $"Opened ($output_svg)"
  } catch {
    print $"Flamegraph saved to ($output_svg)"
  }

  # Show top [dots] hotspots
  print ""
  print "=== Top [dots] Hotspots ==="

  # Parse the profile and aggregate samples by location
  let hotspots = ($dots_content
    | lines
    | par-each { |line|
      let parts = ($line | split row " ")
      let count = ($parts | last | into int | default 0)
      let stack = ($parts | drop 1 | str join " ")
      let frames = ($stack | split row ";")
      $frames | where { |f| $f | str contains "[dots]" } | each { |frame|
        { location: $frame, count: $count }
      }
    }
    | flatten
    | group-by location
    | items { |loc, entries| { location: $loc, total: ($entries | get count | math sum) } }
    | sort-by total --reverse
    | take 20)

  $hotspots | each { |h| print $"($h.total) ($h.location)" } | ignore

  # Show stats
  print ""
  print "=== Evaluation Stats ==="
  if $stats != null {
    let cpu_time = $stats | get cpuTime | math round --precision 2
    let gc_time = $stats | get time.gc | math round --precision 2
    let gc_fraction = $stats | get time.gcFraction | into float | $in * 100 | math round --precision 1
    let envs = $stats | get envs.number
    let list_elems = $stats | get list.elements
    let list_concats = $stats | get list.concats
    let values = $stats | get values.number
    let symbols = $stats | get symbols.number
    let sets = $stats | get sets.number
    let sets_elems = $stats | get sets.elements
    let thunks = $stats | get nrThunks
    let fn_calls = $stats | get nrFunctionCalls

    print $"CPU Time:       ($cpu_time)s"
    print $"GC Time:        ($gc_time)s \(($gc_fraction)%\)"
    print $"Function Calls: ($fn_calls)"
    print $"Thunks:         ($thunks)"
    print $"Environments:   ($envs)"
    print $"Values:         ($values)"
    print $"Symbols:        ($symbols)"
    print $"Sets:           ($sets) \(($sets_elems) elements\)"
    print $"Lists:          ($list_elems) elements \(($list_concats) concats\)"
  } else {
    print "Stats not available"
  }
}

# Cross-platform file opener
def open-file [path: string] {
  match (uname | get kernel-name) {
    "Darwin" => (^open $path)
    "Linux" => (xdg-open $path)
  }
}

# Auto-detect the default flake output based on current host
def get-default-flake-output [] {
  let hostname = (hostname)
  let kernel = (uname | get kernel-name)
  match $kernel {
    "Darwin" => $".#darwinConfigurations.($hostname).system"
    "Linux" => $".#nixosConfigurations.($hostname).config.system.build.toplevel"
    _ => ".#darwinConfigurations.nox.system"
  }
}
