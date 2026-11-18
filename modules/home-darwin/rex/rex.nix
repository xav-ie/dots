# Rex: terminal multiplexer. Rex.app itself is installed by hand and updates
# itself (Sparkle); everything else it would set up imperatively is declared
# here instead:
#
#   - the rex CLI, xterm-rex terminfo and ssh guard  (upstream programs.rex)
#   - ~/.config/rex/init.lua                         (live repo symlink)
#   - the agent skill `rex skill setup` installs     (~/.claude, ~/.agents)
#   - the Codex SessionStart hook                    (~/.codex/hooks.json)
#   - Rex.app's Settings choices                     (defaults domain)
#
# The Claude Code SessionStart hook lives in modules/claude/managed-settings.json:
# allowManagedHooksOnly ignores hooks in user settings.json, where Rex puts it.
# See README.md for the keybinding cheat sheet and a guide.
{ inputs, ... }:
{
  flake.modules.homeManager.darwin =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      # Rex's server starts shells with launchd's bare PATH (/usr/bin:/bin:…),
      # and nushell's config expects to inherit nix's PATH rather than build
      # it. A login zsh sources nix-darwin's /etc/zshenv (nix profiles on
      # PATH, NIX_* vars), then hands the terminal to a login nu.
      rexShell = pkgs.writeScriptBin "rex-shell" ''
        #!/bin/zsh -l
        exec ${config.programs.nushell.package}/bin/nu --login "$@"
      '';
    in
    {
      imports = [ inputs.rex.homeManagerModules.default ];

      home.packages = [ rexShell ];

      # Installs rex on PATH (hooks and the skill call bare `rex`), writes
      # xterm-rex to ~/.terminfo and includes the ssh guard via programs.ssh.
      # `config` stays null: init.lua is linked out-of-store below instead.
      programs.rex.enable = true;

      # Out-of-store symlink so Rex's Reload Config picks up edits to the live
      # repo checkout without a rebuild.
      xdg.configFile."rex/init.lua".source =
        config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/modules/home-darwin/rex/init.lua";

      # Inside Rex, prefer the CLI bundled with the running app over the pinned
      # flake one, as Rex's docs recommend (nix-darwin's fixed PATH drops it).
      programs.nushell.extraEnv = ''
        if ($env.REX_BIN_DIR? | is-not-empty) {
          $env.PATH = ($env.PATH | split row (char esep) | prepend $env.REX_BIN_DIR)
        }
      '';
      programs.zsh.initContent = ''
        if [ -n "$REX_BIN_DIR" ]; then
          export PATH="$REX_BIN_DIR:$PATH"
        fi
      '';

      # What `rex skill setup` installs, frozen into the store so it can't drift.
      # The skill is a stub that runs `rex __internal skill`, so its guide still
      # follows the installed Rex version.
      # force: Rex.app re-runs `rex skill setup` when its agent settings change
      # (e.g. session naming), replacing these links with plain files; the next
      # switch puts the declared ones back instead of failing on a clobber.
      home.file = {
        ".claude/skills/rex/SKILL.md" = {
          source = ./agents/SKILL.md;
          force = true;
        };
        # Shared skill dir read by Codex, OpenCode and Pi.
        ".agents/skills/rex/SKILL.md" = {
          source = ./agents/SKILL.md;
          force = true;
        };
        ".codex/hooks.json" = {
          source = ./agents/codex-hooks.json;
          force = true;
        };
      };

      # Rex.app Settings, re-applied on every switch: change them here, not in
      # the Settings window (it would be reset). A key only appears in the
      # domain once a setting leaves its default, so to find a new one: export
      # the domain, change the setting in the UI, and diff.
      home.activation.rexDefaults =
        let
          settings = {
            # Themes & appearance
            "Workspace.darkThemeID" = "neon-arcade";
            "Workspace.lightThemeID" = "merino-light";
            "Workspace.interfaceStyle" = "blendTheme";
            "Workspace.usesPaneGlass" = false;
            "Workspace.animationStyle" = "snappy";
            "Workspace.paneDensity" = "comfortable";
            "Workspace.inactivePaneFadeMode" = "both";
            "Workspace.notificationPosition" = "bottom-right";
            # Sidebar & activity
            "Workspace.sidebarTextPointSize" = 13.0;
            "Workspace.preservesWindowWidthOnSidebarToggle" = true;
            "Workspace.activityGrouping" = "priority";
            "Workspace.experiments.usesNewQuickSwitcher" = false;
            # Terminal
            "Workspace.terminalFontName" = "Maple Mono NF"; # from dots fonts.nix
            "Workspace.terminalFontPointSize" = 13.0;
            # Stable profile path, so the setting survives nushell updates.
            "Workspace.terminalStartupCommand" = "${config.home.profileDirectory}/bin/rex-shell";
            "Workspace.terminalCopyOnSelect" = true;
            "Workspace.terminalSmoothScrolling" = true;
            "Workspace.terminalUseThemePalette" = false;
            "Workspace.terminalUsesDisplayP3" = true;
            "Workspace.cursorShadersEnabled" = true;
            "Workspace.cursorShader" = "comet";
            # Agents rename their session after the task. Must match the
            # skill stub and hooks, which omit --feature-session-naming=false.
            "rex.agents.names-sessions" = true;
            "rex.developer-mode-enabled" = true;
            # Updates (Sparkle)
            "SUAutomaticallyUpdate" = true;
            "SUEnableAutomaticChecks" = true;
          };
          typeFlag =
            v:
            if builtins.isBool v then
              "-bool ${lib.boolToString v}"
            else if builtins.isFloat v then
              "-float ${toString v}"
            else if builtins.isInt v then
              "-int ${toString v}"
            else
              "-string ${lib.escapeShellArg v}";
        in
        lib.hm.dag.entryAfter [ "writeBoundary" ] (
          lib.concatStringsSep "\n" (
            lib.mapAttrsToList (
              k: v: "run /usr/bin/defaults write com.superlogical.rex ${lib.escapeShellArg k} ${typeFlag v}"
            ) settings
          )
        );
    };
}
