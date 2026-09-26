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

      # Run `herdr integration install <id>` in a throwaway HOME and lift the
      # files it writes at `rels` (relative to HOME) into the store, keeping that
      # layout. `seed` creates whatever dirs/files the installer demands first.
      # We extract rather than vendor, so the hook/plugin can never drift from
      # the installed herdr — it rebuilds whenever pkgs.herdr bumps. herdr also
      # touches config files here (settings.json etc.); those are discarded with
      # the temp HOME.
      #
      # `rels` is a list because an integration is not always one file: opencode
      # ships a pane plugin, a TUI plugin and the tui.jsonc that loads it, and
      # `herdr integration status` reports "needs repair" if any is missing.
      mkHerdrIntegration =
        {
          id,
          rels,
          mode ? "644",
          seed ? "",
          rewriteHome ? false,
        }:
        pkgs.runCommand "herdr-integration-${id}" { } # sh
          ''
            export HOME="$(mktemp -d)"
            ${seed}
            ${pkgs.herdr}/bin/herdr integration install ${id}
            ${lib.concatMapStringsSep "\n" (rel: ''install -D -m${mode} "$HOME/${rel}" "$out/${rel}"'') rels}
            ${lib.optionalString rewriteHome ''
              # Some installers reference sibling files by absolute path (kimi's
              # config.toml names its hook that way). Point those at where the
              # files actually get deployed, not at the throwaway build HOME.
              grep -rl "$HOME" "$out" \
                | xargs -r sed -i "s#$HOME#${config.home.homeDirectory}#g"
            ''}
          '';

      integrations = {
        claude = {
          rels = [ ".claude/hooks/herdr-agent-state.sh" ];
          mode = "755";
          seed = ''
            mkdir -p "$HOME/.claude/hooks"
            echo '{}' > "$HOME/.claude/settings.json"
          '';
        };

        # The installer writes a hook AND registers nine SessionStart/Stop/…
        # events in config.toml that invoke it by absolute path, so both files
        # ship together and the path is rewritten to the deployed one. 755
        # covers the hook; the mode is harmless on the toml.
        kimi = {
          rels = [
            ".kimi-code/config.toml"
            ".kimi-code/hooks/herdr-agent-state.sh"
          ];
          mode = "755";
          seed = ''mkdir -p "$HOME/.kimi-code"'';
          rewriteHome = true;
        };

        opencode = {
          rels = [
            ".config/opencode/herdr-tui-session.js"
            ".config/opencode/plugins/herdr-agent-state.js"
            ".config/opencode/tui.jsonc"
          ];
          seed = ''mkdir -p "$HOME/.config/opencode"'';
        };

        pi = {
          rels = [ ".pi/agent/extensions/herdr-agent-state.ts" ];
          seed = ''mkdir -p "$HOME/.pi/agent/extensions"'';
        };
      };

      # Each integration's files, deployed where its agent auto-discovers them.
      integrationFiles = lib.concatMapAttrs (
        id: spec:
        let
          drv = mkHerdrIntegration ({ inherit id; } // spec);
        in
        lib.listToAttrs (map (rel: lib.nameValuePair rel { source = "${drv}/${rel}"; }) spec.rels)
      ) integrations;

      # Shell completions, generated from the binary (no drift). zsh lands in the
      # standard site-functions dir so the profile fpath + compinit pick it up
      # automatically; nushell has no such scan, so its module is `use`d by path
      # below.
      herdrCompletions = pkgs.runCommand "herdr-completions" { } ''
        mkdir -p "$out/share/zsh/site-functions"
        ${pkgs.herdr}/bin/herdr completion zsh > "$out/share/zsh/site-functions/_herdr"
        ${pkgs.herdr}/bin/herdr completion nushell > "$out/herdr.nu"
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
      home.file = integrationFiles;
    };
}
