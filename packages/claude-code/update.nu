#!/usr/bin/env nu

# Update claude-code package sources
# Usage: update-claude-code [version] [--cooldown-days N] [--npm-version VER]
#
# Without flags: tracks the latest GCS `stable` and the latest npm version.
# With --cooldown-days N: picks the newest version published at least N days
# ago, for both native (GCS) and npm. Use this for the daily auto-update
# workflow so freshly cut releases get a quarantine window.

const GCS_BUCKET = "https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases"
const GCS_API = "https://storage.googleapis.com/storage/v1/b/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/o"

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
# Probes per-version object metadata to read `timeCreated`.
def resolve_native_version [cooldown_days: int] {
  let cutoff = ((date now) - ($cooldown_days * 1day))
  print $"  [Native] Selecting newest version older than ($cooldown_days) days..."
  let listing = (http get $"($GCS_API)?prefix=claude-code-releases/&delimiter=/")
  let versions = (sort_versions ($listing.prefixes
    | each {|p| $p | str trim --right --char '/' | path basename })) | reverse
  for ver in $versions {
    let url = $"($GCS_API)/claude-code-releases%2F($ver)%2Flinux-x64%2Fclaude"
    let meta = (try { http get $url } catch { null })
    if $meta == null { continue }
    let created = $meta.timeCreated | into datetime
    if $created <= $cutoff {
      let date_str = $created | format date '%Y-%m-%d'
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
  let times = npm view @anthropic-ai/claude-code time --json | from json
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

# Main entry point
def main [
  version?: string                # Pin native version. Skips stable/cooldown.
  --cooldown-days: int = 0        # Hold updates until this old before bumping.
  --npm-version: string = ""      # Pin npm version. Skips latest/cooldown.
] {
  # Resolve target native version
  let ver = if not ($version | is-empty) {
    $version
  } else if $cooldown_days > 0 {
    resolve_native_version $cooldown_days
  } else {
    print "Fetching stable version..."
    http get $"($GCS_BUCKET)/stable" | str trim
  }

  # Resolve target npm version
  let target_npm = if not ($npm_version | is-empty) {
    $npm_version
  } else if $cooldown_days > 0 {
    resolve_npm_version $cooldown_days
  } else {
    print "Fetching latest npm version..."
    npm view @anthropic-ai/claude-code version | str trim
  }

  # Load existing sources.json if it exists
  let existing = if ("sources.json" | path exists) {
    open sources.json
  } else {
    null
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
}
