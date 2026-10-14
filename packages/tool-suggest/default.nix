# tool-suggest: the one true source for executor tool suggestions (ported
# from the former modules/claude/tool-suggest.nu). The deployed executable is
# a pinned-bun wrapper around the TypeScript entrypoint, so claude's hooks and
# the opencode plugin shim (src/opencode-plugin.ts) run byte-identical code
# from one store path. `bun build --compile` is deliberately not used: its
# temp-file dance fails with EEXIST on darwin builders.
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
    # The build runs `bun cli.ts selftest`, and bun's JIT is SIGKILLed by the
    # macOS sandbox-exec profile (same as claude-carapace-spec running
    # `claude --help`): build outside the chroot on darwin, sandboxed on
    # linux.
    __noChroot = pkgs.stdenv.hostPlatform.isDarwin;
    meta.mainProgram = "tool-suggest";
  }
  # sh
  ''
    tsc --noEmit --project ${src}/tsconfig.json --pretty false
    mkdir -p $out/bin $out/lib/tool-suggest
    cp -r ${src}/src/. $out/lib/tool-suggest/
    # The wrapper depends on these helpers, so a naming/logic regression
    # fails the build.
    ${pkgs.bun}/bin/bun $out/lib/tool-suggest/cli.ts selftest | grep -q '^ok$'
    cat > $out/bin/tool-suggest <<EOF
    #!${pkgs.runtimeShell}
    exec ${pkgs.bun}/bin/bun $out/lib/tool-suggest/cli.ts "\$@"
    EOF
    chmod +x $out/bin/tool-suggest
  ''
