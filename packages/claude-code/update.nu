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
    let tmp_file = $"/tmp/claude-($p.platform)"
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

# Fetch and compute hashes for npm package
def fetch_npm [
  existing?: record
  --unchanged = false
] {
  # Get latest npm version
  print "  [NPM] Fetching latest version..."
  let npm_version = (npm view @anthropic-ai/claude-code version | str trim)

  if $unchanged {
    print "  [NPM] Reusing hashes (version unchanged)"
    return {
      version: $existing.npm.version
      hash: $existing.npm.hash
      npmDepsHash: $existing.npm.npmDepsHash
      packageLockJson: $existing.npm.packageLockJson
    }
  }

  print $"  [NPM] Computing hashes for version ($npm_version)..."
  let npm_url = $"https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-($npm_version).tgz"
  print $"  [NPM] Downloading from ($npm_url)..."

  let npm_tmp = "/tmp/claude-code-npm.tgz"
  http get $npm_url | save -f $npm_tmp
  let npm_hash = (nix hash file $npm_tmp --sri | str trim)
  print $"  [NPM] Package hash: ($npm_hash)"

  print "  [NPM] Computing npmDepsHash..."
  let extract_dir = (mktemp -d)
  tar -xzf $npm_tmp -C $extract_dir
  let package_dir = (ls $extract_dir | get name | first)

  # Check if package-lock.json exists
  let lock_file = $"($package_dir)/package-lock.json"

  # Generate or use existing package-lock.json
  if (not ($lock_file | path exists)) {
    print $"  [NPM] No package-lock.json found, generating from package.json..."
    let original_dir = $env.PWD
    cd $package_dir
    npm install --package-lock-only --ignore-scripts | complete
    cd $original_dir
  }

  if (not ($lock_file | path exists)) {
    print $"  [NPM] Error: Failed to generate package-lock.json"
    rm -rf $extract_dir
    rm $npm_tmp
    return {
      version: $npm_version
      hash: $npm_hash
      npmDepsHash: ""
      packageLockJson: ""
    }
  }

  print $"  [NPM] Running prefetch-npm-deps on ($lock_file)"
  let prefetch_result = (do {
    nix run nixpkgs#prefetch-npm-deps $lock_file
  } | complete)

  let npm_deps_hash = if ($prefetch_result.exit_code == 0) {
    $prefetch_result.stdout | str trim
  } else {
    print $"  [NPM] Error running prefetch-npm-deps: ($prefetch_result.stderr)"
    ""
  }

  print $"  [NPM] npmDepsHash: ($npm_deps_hash)"

  # Read package-lock.json as raw text to preserve exact formatting
  print $"  [NPM] Reading package-lock.json..."
  let lock_content = (open --raw $lock_file)

  rm -rf $extract_dir
  rm $npm_tmp

  {
    version: $npm_version
    hash: $npm_hash
    npmDepsHash: $npm_deps_hash
    packageLockJson: $lock_content
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
