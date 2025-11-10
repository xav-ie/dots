#!/usr/bin/env nu

# Update claude-code package sources
# Usage: update-claude-code [version]
# If version is not provided, fetches the current stable version

def main [version?: string] {
  let gcs_bucket = "https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases"

  # Get version from argument or fetch stable
  let ver = if ($version | is-empty) {
    print "Fetching stable version..."
    http get $"($gcs_bucket)/stable" | str trim
  } else {
    $version
  }

  print $"Updating to version: ($ver)"

  # Define platforms to update
  let platforms = [
    { nix: "x86_64-linux", platform: "linux-x64" }
    { nix: "aarch64-linux", platform: "linux-arm64" }
    { nix: "x86_64-darwin", platform: "darwin-x64" }
    { nix: "aarch64-darwin", platform: "darwin-arm64" }
  ]

  # Compute hash for each platform
  print "\nComputing hashes for all platforms..."
  let sources = ($platforms | par-each { |p|
    print $"  Computing hash for ($p.platform)..."

    # Download binary to temp file
    let tmp_file = $"/tmp/claude-($p.platform)"
    http get $"($gcs_bucket)/($ver)/($p.platform)/claude" | save -f $tmp_file

    # Compute SRI hash
    let hash = (nix hash file $tmp_file --sri | str trim)

    # Clean up
    rm $tmp_file

    # Return source info
    {
      key: $p.nix
      value: {
        platform: $p.platform
        hash: $hash
      }
    }
  } | transpose -r -d)

  # Create output JSON
  let output = {
    gcs_bucket: $gcs_bucket
    version: $ver
    sources: $sources
  }

  # Write to sources.json in current directory
  $output | to json --indent 2 | save -f sources.json

  print $"\n✅ Updated sources.json with version ($ver)"
  print "Review the changes and commit them to update the package."
}
