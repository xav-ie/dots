{
  lib,
  rustPlatform,
  writableTmpDirAsHomeHook,
  clauhist-src,
}:
rustPlatform.buildRustPackage {
  pname = "clauhist";
  version = clauhist-src.shortRev or clauhist-src.rev or "unstable";

  src = clauhist-src;

  cargoHash = "sha256-nMN/4DmO3hD8To4mDO1A8BDaRHh45seSUQseP7Ckszk=";

  # Upstream tests write to $HOME/.cache and $HOME/tmp.
  nativeCheckInputs = [ writableTmpDirAsHomeHook ];

  # External upstream code; don't gate our checks on its clippy hygiene.
  passthru.skipClippy = true;

  meta = {
    description = "Browse Claude Code history across working directories and resume sessions";
    homepage = "https://github.com/lef237/clauhist";
    license = lib.licenses.mit;
    mainProgram = "clauhist";
  };
}
