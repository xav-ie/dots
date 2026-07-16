# herdr: tmux-like, agent-aware terminal multiplexer. Pulled from upstream's own
# flake (via the `herdr` overlay) so it tracks their releases directly.
{
  flake.modules.homeManager.common =
    {
      config,
      pkgs,
      lib,
      inputs,
      ...
    }:
    let
      xduskTheme = pkgs.writeText "herdr-xdusk-theme.toml" (inputs.xdusk.lib.herdrTheme pkgs.lib);

      # Run `herdr integration install <id>` in a throwaway HOME and lift the one
      # file it writes at `rel` (relative to HOME) into the store. `seed` creates
      # whatever dirs/files the installer demands first. We extract rather than
      # vendor, so the hook/plugin can never drift from the installed herdr — it
      # rebuilds whenever pkgs.herdr bumps. herdr also touches config files here
      # (settings.json etc.); those are discarded with the temp HOME.
      mkHerdrIntegration =
        {
          id,
          rel,
          mode ? "644",
          seed ? "",
        }:
        pkgs.runCommand "herdr-integration-${id}" { } ''
          export HOME="$(mktemp -d)"
          ${seed}
          ${pkgs.herdr}/bin/herdr integration install ${id}
          install -D -m${mode} "$HOME/${rel}" "$out/file"
        '';

      claudeHook = mkHerdrIntegration {
        id = "claude";
        rel = ".claude/hooks/herdr-agent-state.sh";
        mode = "755";
        seed = ''
          mkdir -p "$HOME/.claude/hooks"
          echo '{}' > "$HOME/.claude/settings.json"
        '';
      };

      opencodePlugin = mkHerdrIntegration {
        id = "opencode";
        rel = ".config/opencode/plugins/herdr-agent-state.js";
        seed = ''mkdir -p "$HOME/.config/opencode"'';
      };

      piExtension = mkHerdrIntegration {
        id = "pi";
        rel = ".pi/agent/extensions/herdr-agent-state.ts";
        seed = ''mkdir -p "$HOME/.pi/agent/extensions"'';
      };

      # Shell completions, generated from the binary (no drift). zsh lands in the
      # standard site-functions dir so the profile fpath + compinit pick it up
      # automatically; nushell has no such scan, so its module is `use`d by path
      # below.
      herdrCompletions = pkgs.runCommand "herdr-completions" { } ''
        mkdir -p "$out/share/zsh/site-functions"
        ${pkgs.herdr}/bin/herdr completion zsh > "$out/share/zsh/site-functions/_herdr"
        ${pkgs.herdr}/bin/herdr completion nushell > "$out/herdr.nu"
      '';

      # kimi is bespoke: the installer writes a hook .sh AND registers nine
      # SessionStart/Stop/… events in config.toml, referencing the hook by
      # absolute path. We keep both in one store dir and rewrite that path to
      # this derivation's own $out, so config.toml stays valid without deploying
      # the hook to ~/.kimi-code/hooks (config.toml points straight at the store).
      kimiIntegration = pkgs.runCommand "herdr-integration-kimi" { } ''
        export HOME="$(mktemp -d)"
        mkdir -p "$HOME/.kimi-code"
        ${pkgs.herdr}/bin/herdr integration install kimi
        install -D -m755 "$HOME/.kimi-code/hooks/herdr-agent-state.sh" \
          "$out/herdr-agent-state.sh"
        sed "s#$HOME/.kimi-code/hooks/herdr-agent-state.sh#$out/herdr-agent-state.sh#g" \
          "$HOME/.kimi-code/config.toml" > "$out/config.toml"
      '';
    in
    {
      # herdrCompletions on PATH puts _herdr on the zsh fpath (auto-loaded by
      # compinit via programs.zsh.enableCompletion).
      home.packages = [
        pkgs.herdr
        herdrCompletions
      ];

      # Load herdr's nushell completions (env.nu already ran, so this just needs
      # the module path). Merges with nushell.nix's extraConfig.
      programs.nushell.extraConfig = "use ${herdrCompletions}/herdr.nu *";

      # Out-of-store symlink so `herdr server reload-config` picks up edits to
      # the live repo checkout without a rebuild.
      xdg.configFile."herdr/config.toml".source =
        config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/modules/home/herdr/config.toml";

      home.activation.herdrTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run ${pkgs.pkgs-mine.toml-merge}/bin/toml-merge \
          "${config.dotFilesDir}/modules/home/herdr/config.toml" \
          ${xduskTheme}
      '';

      # Deploy each integration where its agent auto-discovers it, so new
      # machines get herdr agent-state reporting without running any installer.
      # claude's settings.json (managed elsewhere) invokes the hook as
      # `~/.claude/hooks/herdr-agent-state.sh session`.
      home.file = {
        ".claude/hooks/herdr-agent-state.sh".source = "${claudeHook}/file";
        ".config/opencode/plugins/herdr-agent-state.js".source = "${opencodePlugin}/file";
        ".pi/agent/extensions/herdr-agent-state.ts".source = "${piExtension}/file";
        ".kimi-code/config.toml".source = "${kimiIntegration}/config.toml";
      };
    };
}
