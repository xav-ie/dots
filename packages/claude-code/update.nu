#!/usr/bin/env nu

# Update claude-code package sources
# Usage: update-claude-code [version]
# If version is not provided, fetches the current stable version

const GCS_BUCKET = "https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases"

const PLATFORMS = [
  { nix: "x86_64-linux", platform: "linux-x64" }
  { nix: "aarch64-linux", platform: "linux-arm64" }
  { nix: "x86_64-darwin", platform: "darwin-x64" }
  { nix: "aarch64-darwin", platform: "darwin-arm64" }
]

# Fetch and compute hashes for native binaries
def fetch_native [
  version: string
  existing?: record
  --unchanged = false
] {
  if $unchanged {
    print "  [Native] Reusing platform hashes (version unchanged)"
    return {
      version: $version
      gcs_bucket: $GCS_BUCKET
      sources: $existing.native.sources
    }
  }

  print "  [Native] Computing hashes for all platforms..."
  let sources = ($PLATFORMS | par-each { |p|
    print $"  [Native] Computing hash for ($p.platform)..."
    let tmp_file = (mktemp -t claude-XXXX)
    http get $"($GCS_BUCKET)/($version)/($p.platform)/claude" | save -f $tmp_file
    let hash = (nix hash file $tmp_file --sri | str trim)
    rm $tmp_file
    {
      key: $p.nix
      value: {
        platform: $p.platform
        hash: $hash
      }
    }
  } | transpose -r -d)

  {
    version: $version
    gcs_bucket: $GCS_BUCKET
    sources: $sources
  }
}

# Fetch and compute per-platform tarball hashes for the npm registry.
# Since @anthropic-ai/claude-code 2.1.113, each platform ships its own tarball
# containing a prebuilt Bun binary at `package/claude` (same binary as GCS).
def fetch_npm [
  existing?: record
  --unchanged = false
] {
  print "  [NPM] Fetching latest version..."
  let npm_version = (npm view @anthropic-ai/claude-code version | str trim)

  if $unchanged {
    print "  [NPM] Reusing platform hashes (version unchanged)"
    return {
      version: $npm_version
      sources: $existing.npm.sources
    }
  }

  print $"  [NPM] Computing per-platform tarball hashes for ($npm_version)..."
  let sources = ($PLATFORMS | par-each { |p|
    let url = $"https://registry.npmjs.org/@anthropic-ai/claude-code-($p.platform)/-/claude-code-($p.platform)-($npm_version).tgz"
    print $"  [NPM] Computing hash for ($p.platform)..."
    let tmp_file = (mktemp -t claude-npm-XXXX --suffix .tgz)
    http get $url | save -f $tmp_file
    let hash = (nix hash file $tmp_file --sri | str trim)
    rm $tmp_file
    {
      key: $p.nix
      value: {
        platform: $p.platform
        hash: $hash
      }
    }
  } | transpose -r -d)

  {
    version: $npm_version
    sources: $sources
  }
}

# Main entry point
def main [version?: string] {
  # Get version from argument or fetch stable
  let ver = if ($version | is-empty) {
    print "Fetching stable version..."
    http get $"($GCS_BUCKET)/stable" | str trim
  } else {
    $version
  }

  # Load existing sources.json if it exists
  let existing = if ("sources.json" | path exists) {
    open sources.json
  } else {
    null
  }

  # Print version info
  if ($existing != null and "native" in $existing) {
    print $"Previous native version: ($existing.native.version)"
    if ("npm" in $existing and "version" in $existing.npm) {
      print $"Previous npm version: ($existing.npm.version)"
    }
  }
  print $"Target native version: ($ver)"

  # Check if versions are unchanged
  let native_unchanged = ($existing != null and "native" in $existing and $existing.native.version == $ver)
  # Need to fetch current npm version to check if it's unchanged
  let current_npm = (npm view @anthropic-ai/claude-code version | str trim)
  let npm_unchanged = ($existing != null and "npm" in $existing and "version" in $existing.npm and $existing.npm.version == $current_npm)

  if ($native_unchanged and $npm_unchanged) {
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
      type: "native"
      task: { fetch_native $ver $existing --unchanged=$native_unchanged }
    }
    {
      type: "npm"
      task: { fetch_npm $existing --unchanged=$npm_unchanged }
    }
  ] | par-each { |item|
    {
      type: $item.type
      result: (do $item.task)
    }
  })

  let native = ($results | where type == "native" | get 0.result)
  let npm = ($results | where type == "npm" | get 0.result)

  # Create output JSON with restructured format
  let output = {
    native: $native
    npm: $npm
  }

  # Write to sources.json in current directory
  $output | to json --indent 2 | save -f sources.json
  "\n" | save --append sources.json

  print $"\n✅ Updated sources.json"
  print $"  Native version: ($native.version)"
  print $"  NPM version: ($npm.version)"
  print "Review the changes and commit them to update the package."
}
