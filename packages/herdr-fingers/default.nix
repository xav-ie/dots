# tmux-fingers for herdr: a key labels every path, URL, SHA, IP and number in
# the focused pane; typing a label copies it (Shift pastes, Ctrl opens).
#
# Upstream's install path is `herdr plugin install`, whose [[build]] step runs
# cargo inside the checkout. We build with nix and drop that step, so the plugin
# root is a read-only store path. modules/home/herdr/herdr-fingers.nix registers it.
{
  fetchFromGitHub,
  lib,
  rustPlatform,
}:
let
  version = "0.1.0";
in
rustPlatform.buildRustPackage {
  pname = "herdr-fingers";
  inherit version;

  src = fetchFromGitHub {
    owner = "nathan-poncet";
    repo = "herdr-fingers";
    tag = "v${version}";
    hash = "sha256-bQoNLqkeNyxwa8Gxx4lUsby2ahrHwigBG24wJsm07nU=";
  };

  # importCargoLock rather than cargoHash for the same reason as herdr-fwd:
  # fetchCargoVendor's User-Agent gets 403 from crates.io. Re-copy Cargo.lock
  # from the tag when bumping version.
  cargoDeps = rustPlatform.importCargoLock { lockFile = ./Cargo.lock; };

  # The manifest invokes the binary by the relative path cargo would have
  # produced, so keep that layout as a symlink rather than rewriting commands.
  postInstall = ''
    root="$out/share/herdr-fingers"
    install -d "$root/target/release"
    ln -s "$out/bin/herdr-fingers" "$root/target/release/herdr-fingers"

    # Strip [[build]]: cargo cannot write into the store, and nix just built it.
    sed '/^\[\[build\]\]/,/^$/d' herdr-plugin.toml > "$root/herdr-plugin.toml"
  '';

  passthru = {
    pluginRoot = "share/herdr-fingers";
    # External upstream code; don't gate our checks on its clippy hygiene.
    skipClippy = true;
  };

  meta = {
    description = "tmux-fingers for herdr: copy, paste or open anything on screen by typing a hint";
    homepage = "https://github.com/nathan-poncet/herdr-fingers";
    license = lib.licenses.mit;
    mainProgram = "herdr-fingers";
    platforms = lib.platforms.unix;
  };
}
