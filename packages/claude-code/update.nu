#!/usr/bin/env nu

# Update claude-code package sources
# Usage: update-claude-code [version] [--cooldown-days N] [--npm-version VER] [--force]
#
# Without flags: tracks the latest GCS `stable` and the latest npm version.
# With --cooldown-days N: picks the newest version published at least N days
# ago, for both native (GCS) and npm. Use this for the daily auto-update
# workflow so freshly cut releases get a quarantine window.
#
# The actual sources.json bump is gated to at most once per 30 days unless
# --force is passed. Changelog reporting always happens regardless of the gate.

const GCS_BUCKET = "https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases"
const CHANGELOG_URL = "https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md"
# Resolve npm targets from a per-platform package, not the `@anthropic-ai/claude-code`
# meta package: the two publish out of step, and the tarballs hashed below only
# exist under the per-platform names.
const NPM_PKG = "@anthropic-ai/claude-code-linux-x64"
# Count of releases published past the pinned version. Read by the statusline
# (modules/claude/statusline.nu) so it never has to hit the network itself.
const PENDING_CACHE = "~/.cache/claude-code-pending" | path expand
# Unix timestamp of the last sources.json bump. Gates the auto-update interval.
const LAST_BUMP = "~/.cache/claude-code-last-bump" | path expand

const PLATFORMS = [
  {nix: "x86_64-linux", platform: "linux-x64"}
  {nix: "aarch64-linux", platform: "linux-arm64"}
  {nix: "x86_64-darwin", platform: "darwin-x64"}
  {nix: "aarch64-darwin", platform: "darwin-arm64"}
]

# Fetch and compute hashes for native binaries
def fetch_native [version: string, existing?: record, --unchanged] {
  if $unchanged {
    print "  [Native] Reusing platform hashes (version unchanged)"
    return {version: $version, gcs_bucket: $GCS_BUCKET, sources: $existing.native.sources}
  }

  print "  [Native] Computing hashes for all platforms..."
  let sources = ($PLATFORMS | par-each { |p|
    print $"  [Native] Computing hash for ($p.platform)..."
    let tmp_file = (mktemp -t claude-XXXX)
    http get $"($GCS_BUCKET)/($version)/($p.platform)/claude" | save -f $tmp_file
    let hash = nix hash file $tmp_file --sri | str trim
    rm $tmp_file
    {
      key: $p.nix
      value: {
        platform: $p.platform
        hash: $hash
      }
    }
  } | transpose -r -d)

  {version: $version, gcs_bucket: $GCS_BUCKET, sources: $sources}
}

# Fetch and compute per-platform tarball hashes for the npm registry.
# Since @anthropic-ai/claude-code 2.1.113, each platform ships its own tarball
# containing a prebuilt Bun binary at `package/claude` (same binary as GCS).
def fetch_npm [npm_version: string, existing?: record, --unchanged] {
  if $unchanged {
    print "  [NPM] Reusing platform hashes (version unchanged)"
    return {version: $npm_version, sources: $existing.npm.sources}
  }

  print $"  [NPM] Computing per-platform tarball hashes for ($npm_version)..."
  let sources = ($PLATFORMS | par-each { |p|
    let url = $"https://registry.npmjs.org/@anthropic-ai/claude-code-($p.platform)/-/claude-code-($p.platform)-($npm_version).tgz"
    print $"  [NPM] Computing hash for ($p.platform)..."
    let tmp_file = (mktemp -t claude-npm-XXXX --suffix .tgz)
    http get $url | save -f $tmp_file
    let hash = nix hash file $tmp_file --sri | str trim
    rm $tmp_file
    {
      key: $p.nix
      value: {
        platform: $p.platform
        hash: $hash
      }
    }
  } | transpose -r -d)

  {version: $npm_version, sources: $sources}
}

# Sort a list of "X.Y.Z" version strings ascending by numeric segment.
def sort_versions [versions: list<string>] {
  $versions
  | each {|v|
        let parts = $v | parse --regex '^(?P<a>\d+)\.(?P<b>\d+)\.(?P<c>\d+)$'
        if ($parts | is-empty) { null } else {
          {
            ver: $v
            key: [($parts.0.a | into int) ($parts.0.b | into int) ($parts.0.c | into int)]
          }
        }
      }
  | where {|r| $r != null}
  | sort-by key
  | get ver
}

# Pick the newest GCS native version published at least cooldown_days ago.
# Uses npm publish dates (both tracks share releases) and verifies the binary
# exists on GCS via HEAD request, since the GCS listing API is not public.
def resolve_native_version [cooldown_days: int] {
  let cutoff = ((date now) - ($cooldown_days * 1day))
  print $"  [Native] Selecting newest version older than ($cooldown_days) days..."
  let times = npm view @anthropic-ai/claude-code time --json | from json
  let eligible = ($times
    | transpose version published
    | where version != "created" and version != "modified"
    | update published {|r| $r.published | into datetime}
    | where published <= $cutoff)
  let ranked = (sort_versions ($eligible | get version)) | reverse
  for ver in $ranked {
    let url = $"($GCS_BUCKET)/($ver)/linux-x64/claude"
    let exists = (try {
      http head $url | ignore
      true
    } catch { false })
    if $exists {
      let when = $eligible | where version == $ver | get 0.published
      let date_str = $when | format date '%Y-%m-%d'
      print $"  [Native] Selected ($ver), published ($date_str)"
      return $ver
    }
  }
  error make {msg: $"No native version older than ($cooldown_days) days found"}
}

# Pick the newest npm version published at least cooldown_days ago.
def resolve_npm_version [cooldown_days: int] {
  let cutoff = ((date now) - ($cooldown_days * 1day))
  print $"  [NPM] Selecting newest version older than ($cooldown_days) days..."
  let times = npm view $NPM_PKG time --json | from json
  let eligible = ($times
    | transpose version published
    | where version != "created" and version != "modified"
    | update published {|r| $r.published | into datetime}
    | where published <= $cutoff)
  let ranked = sort_versions ($eligible | get version)
  if ($ranked | is-empty) {
    error make {msg: $"No npm version older than ($cooldown_days) days found"}
  }
  let chosen = $ranked | last
  let when = $eligible | where version == $chosen | get 0.published
  let date_str = $when | format date '%Y-%m-%d'
  print $"  [NPM] Selected ($chosen), published ($date_str)"
  $chosen
}

# Collapse "X.Y.Z" into one sortable integer.
def ver_num [v: string] {
  let p = $v | split row '.' | each {|s| $s | into int}
  ($p.0 * 1_000_000) + ($p.1 * 1_000) + $p.2
}

# Oldest version currently pinned and newest version targeted, across both
# tracks. One range covers them since npm and native share releases.
def ver_bounds [existing: record, native: string, npm: string] {
  {
    from: (
      [$existing.native.version ($existing.npm?.version? | default $existing.native.version)]
      | sort-by {|v| ver_num $v}
      | first
    )
    to: ([$native $npm] | sort-by {|v| ver_num $v} | last)
  }
}

# Print upstream release notes for every version in (from, to]. Anthropic keeps
# per-version notes in the public repo; a version with no entry there is simply
# absent from the printed range.
def print_changelog [from: string, to: string] {
  if (ver_num $to) <= (ver_num $from) { return }
  let body = try { http get --raw $CHANGELOG_URL } catch { null }
  if $body == null {
    print "\n[Changelog] fetch failed"
    return
  }
  let picked = $body
  | split row "\n## "
  | skip 1
  | where {|s|
        let n = try { ver_num ($s | lines | first | str trim) } catch { 0 }
        $n > (ver_num $from) and $n <= (ver_num $to)
      }
  print $"\n=== Release notes ($from) -> ($to) ==="
  if ($picked | is-empty) {
    print "(no upstream entries for this range)"
  } else {
    print ($picked | each {|s| $"## ($s)" } | str join "\n")
  }
}

# Days between automatic sources.json bumps.
const BUMP_INTERVAL_DAYS = 30
# Quarantine window: the daily auto-updater won't bump to anything fresher.
const QUARANTINE_DAYS = 14

# Main entry point
def main [
  version?: string                # Pin native version. Skips stable/cooldown.
  --cooldown-days: int = 0        # Hold updates until this old before bumping.
  --npm-version: string = ""      # Pin npm version. Skips latest/cooldown.
  --force                         # Bypass the bump-interval gate.
] {
  # Load existing sources.json if it exists
  let existing = if ("sources.json" | path exists) {
    open sources.json
  } else {
    null
  }

  # Resolve target native version
  let resolved_native = if not ($version | is-empty) {
    $version
  } else if $cooldown_days > 0 {
    resolve_native_version $cooldown_days
  } else {
    print "Fetching stable version..."
    http get $"($GCS_BUCKET)/stable" | str trim
  }

  # Resolve target npm version
  let resolved_npm = if not ($npm_version | is-empty) {
    $npm_version
  } else if $cooldown_days > 0 {
    resolve_npm_version $cooldown_days
  } else {
    print "Fetching latest npm version..."
    npm view $NPM_PKG version | str trim
  }

  # Never downgrade: if the resolved target is older than what's pinned, keep
  # the existing version.
  let ver = if ($existing != null and "native" in $existing and (ver_num $resolved_native) < (ver_num $existing.native.version)) {
    $existing.native.version
  } else {
    $resolved_native
  }
  let target_npm = if ($existing != null and "npm" in $existing and "version" in $existing.npm and (ver_num $resolved_npm) < (ver_num $existing.npm.version)) {
    $existing.npm.version
  } else {
    $resolved_npm
  }

  # Print version info
  if $existing != null and "native" in $existing {
    print $"Previous native version: ($existing.native.version)"
    if "npm" in $existing and "version" in $existing.npm {
      print $"Previous npm version: ($existing.npm.version)"
    }
  }
  print $"Target native version: ($ver)"
  print $"Target npm version: ($target_npm)"

  # Always report the changelog and update the pending cache, regardless of
  # whether the bump gate below allows a write.
  if $existing != null {
    let bounds = ver_bounds $existing $ver $target_npm
    if (ver_num $bounds.to) > (ver_num $bounds.from) {
      $"($bounds.from) -> ($bounds.to)" | save -f $PENDING_CACHE
    } else {
      rm -f $PENDING_CACHE
    }

    # Split the pending range at the quarantine boundary, clamped into
    # [from, to]: at or below it is eligible now, above it is still quarantined.
    # With --cooldown-days the target already respects the window, so the whole
    # range is eligible.
    let split = if $cooldown_days == 0 {
      let q_native = try { resolve_native_version $QUARANTINE_DAYS } catch { $ver }
      let q_npm = try { resolve_npm_version $QUARANTINE_DAYS } catch { $target_npm }
      let q_upper = ([$q_native $q_npm] | sort-by {|v| ver_num $v} | last)
      [$bounds.from ([$q_upper $bounds.to] | sort-by {|v| ver_num $v} | first)]
      | sort-by {|v| ver_num $v}
      | last
    } else {
      $bounds.to
    }

    if (ver_num $split) > (ver_num $bounds.from) {
      print_changelog $bounds.from $split
    } else {
      print $"\n=== Nothing past ($bounds.from) is out of quarantine yet ==="
    }
    if (ver_num $bounds.to) > (ver_num $split) {
      print $"\n=== Upcoming: in ($QUARANTINE_DAYS)-day quarantine ==="
      print_changelog $split $bounds.to
    }
  }

  # Check if versions are unchanged
  let native_unchanged = (
    $existing != null and "native" in $existing and $existing.native.version == $ver
  )
  let npm_unchanged = (
    $existing != null and "npm" in $existing and "version" in $existing.npm and $existing.npm.version == $target_npm
  )

  if $native_unchanged and $npm_unchanged {
    print "✅ Both versions unchanged - sources.json is already up to date"
    return
  }

  # Bump-interval gate: skip the actual write unless --force, an explicit
  # version was pinned, or the last bump is older than BUMP_INTERVAL_DAYS.
  let explicit_pin = not ($version | is-empty) or not ($npm_version | is-empty)
  if not $force and not $explicit_pin {
    let last = try { open $LAST_BUMP | str trim | into int } catch { 0 }
    let elapsed_days = ((date now | into int) - $last) / 86_400_000_000_000
    if $elapsed_days < $BUMP_INTERVAL_DAYS {
      let remaining = ($BUMP_INTERVAL_DAYS - ($elapsed_days | math floor))
      print $"\n⏳ Bump gated: last bump was ($elapsed_days | math floor) days ago."
      print $"   Next auto-bump in ~($remaining) days. Use --force to override."
      return
    }
  }

  if $native_unchanged {
    print "Native version unchanged, updating npm only"
  }

  print "\nComputing hashes in parallel..."

  # Run native and npm fetches in parallel
  let results = ([
    {
      type: "native", 
      task: { fetch_native $ver $existing --unchanged=$native_unchanged }
    }
    {
      type: "npm", 
      task: { fetch_npm $target_npm $existing --unchanged=$npm_unchanged }
    }
  ] | par-each { |item|
    {
      type: $item.type
      result: (do $item.task)
    }
  })

  let native = $results | where type == "native" | get 0.result
  let npm = $results | where type == "npm" | get 0.result

  # Create output JSON with restructured format
  let output = {native: $native, npm: $npm}

  # Write to sources.json in current directory
  $output | to json --indent 2 | save -f sources.json
  "\n" | save --append sources.json

  print $"\n✅ Updated sources.json"
  print $"  Native version: ($native.version)"
  print $"  NPM version: ($npm.version)"
  print "Review the changes and commit them to update the package."

  date now | into int | save -f $LAST_BUMP
  rm -f $PENDING_CACHE
}
