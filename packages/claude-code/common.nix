{ pkgs }:
let
  inherit (pkgs)
    lib
    stdenv
    socat
    bubblewrap
    gopls
    rust-analyzer
    ;
in
{
  # Dependencies needed on Linux for sandboxing
  linuxDeps = [
    socat
    bubblewrap
  ];

  # Common wrapper arguments for wrapProgram
  wrapperArgs = lib.concatStringsSep " " [
    "--set DISABLE_AUTOUPDATER 1"
    "--set ENABLE_TOOL_SEARCH true"
    "--set ENABLE_LSP_TOOL true"
    "--set ENABLE_EXPERIMENTAL_MCP_CLI false"
    "--set CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD 1"
    (lib.optionalString stdenv.isLinux "--prefix PATH : ${
      lib.makeBinPath [
        socat
        bubblewrap
        # lsp server support
        gopls
        rust-analyzer
      ]
    }")
  ];

  # Shared meta attributes
  meta =
    description: with lib; {
      inherit description;
      homepage = "https://claude.ai";
      license = licenses.unfree;
      maintainers = [ ];
      mainProgram = "claude";
    };
}
