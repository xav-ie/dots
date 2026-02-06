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

  linuxBinPath = lib.makeBinPath [
    socat
    bubblewrap
    gopls
    rust-analyzer
  ];

  # Environment variables for Claude Code
  # Single source of truth: used by both wrapProgram and tmux agent spawn patches
  envVars = {
    CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD = "1";
    CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1"; # https://code.claude.com/docs/en/agent-teams
    DISABLE_AUTOUPDATER = "1";
    DISABLE_INSTALLATION_CHECKS = "1";
    ENABLE_EXPERIMENTAL_MCP_CLI = "false";
    ENABLE_LSP_TOOL = "true";
    ENABLE_TOOL_SEARCH = "true";
  };
in
{
  inherit envVars;

  # Dependencies needed on Linux for sandboxing
  linuxDeps = [
    socat
    bubblewrap
  ];

  # Common wrapper arguments for wrapProgram
  wrapperArgs = lib.concatStringsSep " " (
    (lib.mapAttrsToList (k: v: "--set ${k} ${v}") envVars)
    ++ lib.optional stdenv.isLinux "--prefix PATH : ${linuxBinPath}"
  );

  # Wrapper script for tmux agent panes: exports env vars and starts /bin/sh
  # Much faster than zsh (no .zshrc) and avoids long env var strings in send-keys
  spawnWrapper = pkgs.writeScript "claude-agent-env" (
    "#!/bin/sh\n"
    + lib.concatStringsSep "\n" (
      lib.mapAttrsToList (k: v: "export ${k}=${lib.escapeShellArg v}") envVars
    )
    + "\nexec /bin/sh\n"
  );

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
