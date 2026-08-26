# Automatic loopback port forwarding for remote herdr sessions: the plugin half
# runs on the machine hosting herdr and the dev servers (praesidium) and reports
# which loopback ports its panes opened; `hfwd` runs on the connecting machine
# (nox) and owns the ssh forwards. VS Code's auto-forward, for `herdr --remote`.
#
# Upstream's install path is `herdr plugin install`, whose [[build]] step curls a
# prebuilt binary into the checkout. We build both binaries with nix instead and
# drop that step, so the plugin root is a read-only store path and nothing is
# fetched at runtime. modules/home/herdr/herdr-fwd.nix registers it.
{
  fetchFromGitHub,
  lib,
  rustPlatform,
}:
let
  version = "0.1.5";
in
rustPlatform.buildRustPackage {
  pname = "herdr-fwd";
  inherit version;

  src = fetchFromGitHub {
    owner = "go-min";
    repo = "herdr-fwd";
    tag = "v${version}";
    hash = "sha256-OJRo6s+HlZApWqlrhDckSXWaNOIhgfDs1bWbVL9Qzrg=";
  };

  # Not cargoHash/fetchCargoVendor: that fetcher sends python-requests' default
  # User-Agent, which crates.io now answers with 403. importCargoLock fetches
  # each crate through fetchurl (curl), which is served normally. The cost is
  # tracking Cargo.lock here — re-copy it from the tag when bumping version.
  cargoDeps = rustPlatform.importCargoLock { lockFile = ./Cargo.lock; };

  # Both modules need things the build sandbox denies: dashboard_actions shells
  # out to the system URL opener, companion binds loopback TCP. They fail with
  # EPERM / "no available local port", not on logic. Everything else still runs
  # (90 of 97 tests), so a real regression elsewhere still fails the build.
  checkFlags = [
    "--skip=plugin::dashboard_actions::dashboard_actions_tests"
    "--skip=local::companion::companion_tests"
  ];

  # The plugin root herdr points `plugin_root` at. The manifest invokes the
  # binary by the relative path cargo would have produced, so we keep that
  # layout and symlink it at the store binary rather than rewriting every
  # command in the manifest.
  postInstall = ''
    root="$out/share/herdr-fwd"
    install -d "$root/target/release"
    ln -s "$out/bin/herdr-fwd-plugin" "$root/target/release/herdr-fwd-plugin"

    # Strip [[build]]: it curls a release archive over the checkout, which is
    # both impossible (read-only store) and redundant (cargo just built it).
    sed '/^\[\[build\]\]/,/^$/d' herdr-plugin.toml > "$root/herdr-plugin.toml"
  '';

  passthru.pluginRoot = "share/herdr-fwd";

  meta = {
    description = "Automatic loopback port forwarding for remote herdr sessions";
    homepage = "https://github.com/go-min/herdr-fwd";
    license = lib.licenses.mit;
    mainProgram = "hfwd";
    platforms = lib.platforms.unix;
  };
}
