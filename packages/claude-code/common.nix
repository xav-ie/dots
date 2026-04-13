{ pkgs }:
let
  inherit (pkgs)
    lib
    stdenv
    bubblewrap
    gopls
    rust-analyzer
    socat
    sox
    ;

  linuxBinPath = lib.makeBinPath [
    bubblewrap
    gopls
    rust-analyzer
    socat
    sox
  ];

  # Keep .claude.json inside ~/.claude/ so all writes stay in one dir (enables bwrap sandboxing)
  # Needs runtime $HOME expansion, so it can't go in envVars (which use --set at build time)
  configDirExport = ''export CLAUDE_CONFIG_DIR="$HOME/.claude"'';

  # Environment variables for Claude Code
  # Single source of truth: used by both wrapProgram and tmux agent spawn patches

  envVars = {
    CLAUBBIT = "1"; # skip TrustDialog render/unmount cycles on startup
    CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD = "1";
    CLAUDE_CODE_DISABLE_BACKGROUND_TASKS = "1"; # hide run_in_background docs/UI
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1"; # skip connectivity polling, changelog, auto-updater
    CLAUDE_CODE_DISABLE_OFFICIAL_MARKETPLACE_AUTOINSTALL = "1"; # skip marketplace plugin auto-install
    CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1"; # https://code.claude.com/docs/en/agent-teams
    DISABLE_AUTOUPDATER = "1";
    DISABLE_ERROR_REPORTING = "1";
    DISABLE_INSTALLATION_CHECKS = "1";
    DISABLE_TELEMETRY = "1"; # skip GrowthBook, tool search indexing, Datadog flush
    ENABLE_EXPERIMENTAL_MCP_CLI = "false";
    ENABLE_LSP_TOOL = "true";
    ENABLE_TOOL_SEARCH = "true";
    NODE_COMPILE_CACHE = "/tmp/claude-code-compile-cache"; # ~3x faster Node.js startup (395ms→120ms)
    SSL_CERT_DIR = "${pkgs.cacert}/etc/ssl/certs"; # silence OpenSSL "Cannot open directory" warning
    SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
  };
in
{
  inherit envVars configDirExport;

  # Common wrapper arguments for wrapProgram (makeBinaryWrapper, no --run support)
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
    + "\nexport CLAUDE_CONFIG_DIR=\"$HOME/.claude\""
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
