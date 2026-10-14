# tool-suggest: the one true source for executor tool suggestions (ported
# from the former modules/claude/tool-suggest.nu). The compiled binary speaks
# the claude-code hook JSON contract on stdin/stdout (UserPromptSubmit /
# PostToolBatch / generic { event, text }), so one artifact serves claude's
# hooks directly and the opencode plugin shim (src/opencode-plugin.ts), which
# spawns it and injects hookSpecificOutput.additionalContext.
{
  pkgs ? import <nixpkgs> { },
}:
let
  # Whole package dir so tsconfig's `include = [ "src" ]` resolves in the
  # store; cleanSource drops .git and friends.
  src = pkgs.lib.cleanSource ./.;
in
pkgs.runCommand "tool-suggest"
  {
    nativeBuildInputs = [
      pkgs.bun
      pkgs.typescript
    ];
    # bun's compile temp files collide (EEXIST .bun-build) inside the macOS
    # sandbox-exec profile, same class of problem as claude-code-extract's
    # JIT kills: build outside the chroot on darwin, sandboxed on linux.
    __noChroot = pkgs.stdenv.hostPlatform.isDarwin;
    meta.mainProgram = "tool-suggest";
  }
  # sh
  ''
    tsc --noEmit --project ${src}/tsconfig.json --pretty false
    mkdir -p $out/bin
    bun build --compile ${src}/src/cli.ts --outfile $out/bin/tool-suggest
    # The wrapper depends on these helpers, so a naming/logic regression
    # fails the build.
    $out/bin/tool-suggest selftest | grep -q '^ok$'
  ''
