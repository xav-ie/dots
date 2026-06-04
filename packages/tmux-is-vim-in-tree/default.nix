{ rustPlatform }:
rustPlatform.buildRustPackage {
  pname = "tmux-is-vim-in-tree";
  version = "0.1.0";
  src = ./.;
  # No external crates, so the lockfile vendors nothing and the build needs no
  # network access or cargoHash.
  cargoLock.lockFile = ./Cargo.lock;
}
