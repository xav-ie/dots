# claude-code

Nix package for [Claude Code](https://claude.ai) - AI-powered coding assistant CLI.

## Installation

Add to your system packages or home-manager configuration:

```nix
{
  environment.systemPackages = with pkgs; [
    claude-code
  ];
}
```

Or use directly:

```bash
NIXPKGS_ALLOW_UNFREE=1 nix run --impure .#claude-code
```

## Updating

This package uses a JSON-based update mechanism. To update to a new version:

1. Navigate to the package directory:

   ```bash
   cd packages/claude-code
   ```

2. Run the update script:

   ```bash
   # Update to latest stable version
   nix run ../../#claude-code-update

   # Or update to a specific version
   nix run ../../#claude-code-update -- 2.0.35
   ```

3. The script will:
   - Fetch the specified version (or latest stable)
   - Download binaries for all supported platforms
   - Compute SRI hashes for each platform
   - Update `sources.json` with the new version and hashes

4. Review and commit the changes to `sources.json`

## How it works

- `sources.json` - Contains version and platform-specific hashes
- `default.nix` - Main derivation, reads from `sources.json`
- `update.nu` - Nushell script to fetch and compute hashes
- `update.nix` - Nix derivation for the update script

The derivation fetches pre-built binaries from Google Cloud Storage and patches them for NixOS.

## Supported Platforms

- `x86_64-linux` (glibc)
- `aarch64-linux` (glibc)
- `x86_64-darwin`
- `aarch64-darwin`
