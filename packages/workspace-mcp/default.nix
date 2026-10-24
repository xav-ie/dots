{
  lib,
  buildNpmPackage,
  nodejs,
  src,
  writeShellScript,
}:
let
  # The server locates its token store by walking up from its own directory for
  # gemini-extension.json, then writing the encrypted token and master key
  # beside it (workspace-server/src/utils/paths.ts). That directory is the Nix
  # store here, so the launcher mirrors the bundle into a writable state dir and
  # runs it from there. Refreshed whenever the store path changes.
  launcher = writeShellScript "workspace-mcp" ''
    set -eu
    state="''${WORKSPACE_MCP_STATE_DIR:-''${XDG_DATA_HOME:-$HOME/.local/share}/workspace-mcp}"
    if [ "$(cat "$state/.store-path" 2>/dev/null || true)" != "@out@" ]; then
      mkdir -p "$state/workspace-server/dist"
      cp -f @out@/lib/workspace-mcp/dist/* "$state/workspace-server/dist/"
      chmod u+w "$state/workspace-server/dist"/*
      echo '{"name":"google-workspace"}' > "$state/gemini-extension.json"
      echo "@out@" > "$state/.store-path"
    fi
    exec ${lib.getExe nodejs} "$state/workspace-server/dist/index.js" "$@"
  '';
in
buildNpmPackage {
  pname = "workspace-mcp";
  version = "0.0.8-${src.shortRev or "unstable"}";

  inherit src;

  # tool-descriptions.patch rewords each tool's MCP description to match the
  # terms people actually search with; applied after event-location.patch.
  patches = [
    ./event-location.patch
    ./tool-descriptions.patch
  ];

  npmDepsHash = "sha256-7PbXyCrT6ICKhZyFugnYxY9hMd0NAmWNfY0BkpAxQtk=";

  # keytar's install script fetches a prebuilt binary from the network. The
  # server imports it lazily and falls back to encrypted-file storage when the
  # import fails, which is what the mcp-proxy backend uses anyway.
  npmFlags = [ "--ignore-scripts" ];

  # esbuild's postinstall (skipped above) is what links the platform binary into
  # node_modules/esbuild; point the JS API at the @esbuild/<platform> package
  # npm already unpacked. nixpkgs' esbuild is too old — the JS API refuses a
  # binary whose version doesn't match exactly.
  preBuild = ''
    export ESBUILD_BINARY_PATH=$PWD/$(echo node_modules/@esbuild/*/bin/esbuild)
  '';

  # Fail the build if a tool's reworded MCP description regresses. Runs the
  # just-built bundle in place (gemini-extension.json sits a few directories
  # up, same as checked out) rather than the installed copy, which needs the
  # launcher's writable-state-dir dance. Listing tools never touches the
  # network or needs real Google credentials — OAuth only happens per-call —
  # so dummy ones are enough. A server bump that renames/rewords a tool makes
  # the patch fail to apply first; this catches the case where it still
  # applies but no longer lands on the right text.
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    WORKSPACE_MCP_STATE_DIR=$(mktemp -d) \
      GOOGLE_OAUTH_CLIENT_ID=check-dummy \
      GOOGLE_OAUTH_CLIENT_SECRET=check-dummy \
      node ${./check-descriptions.js} workspace-server/dist/index.js ${./expected-descriptions.json}
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/workspace-mcp/dist $out/bin
    cp workspace-server/dist/*.js workspace-server/dist/*.map $out/lib/workspace-mcp/dist/
    substitute ${launcher} $out/bin/workspace-mcp --subst-var out
    chmod +x $out/bin/workspace-mcp
    runHook postInstall
  '';

  meta = {
    description = "Google Workspace MCP server (Gmail, Calendar, Drive, Docs, Chat)";
    homepage = "https://github.com/gemini-cli-extensions/workspace";
    license = lib.licenses.asl20;
    mainProgram = "workspace-mcp";
  };
}
