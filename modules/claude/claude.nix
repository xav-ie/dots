{
  flake.modules.homeManager.common =
    {
      config,
      inputs,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.claude;

      # Marketplace submodule (no cfg dependency - safe in outer let)
      marketplaceOpts = _: {
        options = {
          repo = lib.mkOption {
            type = lib.types.str;
            description = "GitHub repository in owner/repo format";
            example = "anthropics/claude-plugins-official";
          };

          src = lib.mkOption {
            type = lib.types.path;
            description = "Flake input source for the marketplace";
            example = "inputs.claude-marketplace-official";
          };
        };
      };

      # Find input name by matching src path against inputs (pure function, safe)
      findInputName =
        src: lib.attrNames inputs |> lib.findFirst (name: inputs.${name}.outPath or null == "${src}") null;

      # A nushell hook script, deployed as two files:
      #   .claude/<name>.nu  -> live, out-of-store symlink (edit without rebuild)
      #   .claude/<name>     -> store wrapper that execs the *pinned* nushell
      #                         against that live source, passing args through.
      # Hooks must be invoked via the wrapper (~/.claude/<name>), NOT the raw
      # .nu, so the interpreter is always the session nushell rather than
      # whatever `nu` a project's devshell happens to put on PATH first — a
      # mismatched (e.g. older) `nu` otherwise breaks the scripts (this is the
      # same reason statusline was already wrapped this way).
      mkNuHook =
        name:
        let
          src = "${config.dotFilesDir}/modules/claude/${name}.nu";
        in
        {
          ".claude/${name}.nu".source = config.lib.file.mkOutOfStoreSymlink src;
          ".claude/${name}".source = pkgs.writeShellScript "claude-${name}" ''
            exec ${lib.getExe config.programs.nushell.package} --stdin ${src} "$@"
          '';
        };

    in
    {
      options.programs.claude = {
        enable = lib.mkEnableOption "Claude Code CLI";

        nativeInstall = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = ''
            Whether to use the native (Bun-based) installation of Claude Code.

            When true: Uses the pre-compiled native binary (faster startup, but has known issues with editor integration).
            When false: Uses the npm/Node.js version (slower startup, but more reliable editor integration).

            Note: The native version has a known bug where it drops keystrokes in external editors (Ctrl+G).
            Using nativeInstall = false resolves this issue by using the npm installation instead.
          '';
        };

        pluginSyncPackage = lib.mkOption {
          type = lib.types.package;
          description = "The claude-plugin-sync package (default set in config when enabled)";
        };

        marketplaces = lib.mkOption {
          type = lib.types.attrsOf (lib.types.submodule marketplaceOpts);
          # Mergeable: the core set is registered below (config), and each
          # feature module can add its own (e.g. modules/wakatime.nix). Defining
          # it as an option `default` would make any per-key definition drop the
          # whole default, so the base lives in config too.
          default = { };
          description = "Claude Code marketplaces pinned from flake inputs";
          example = lib.literalExpression ''
            {
              "claude-plugins-official" = {
                repo = "anthropics/claude-plugins-official";
                src = inputs.claude-marketplace-official;
              };
            }
          '';
        };
      };

      config = lib.mkIf cfg.enable (
        let
          # Move all expensive computations inside mkIf so they're only evaluated when enabled

          # The update script package (in overlay)
          inherit (pkgs) claude-code-update;

          marketplaceInputNames =
            cfg.marketplaces |> lib.mapAttrsToList (_: m: findInputName m.src) |> lib.filter (x: x != null);

          updateMarketplacesPackage = pkgs.writeShellScriptBin "claude-update-marketplaces" ''
            cd "${config.dotFilesDir}"
            exec nix flake lock ${lib.concatMapStringsSep " " (i: "--update-input ${i}") marketplaceInputNames}
          '';

          # Generate known_marketplaces.json from configured marketplaces
          knownMarketplacesJson =
            cfg.marketplaces
            |> lib.mapAttrs (
              name: marketplace: {
                source = {
                  source = "github";
                  inherit (marketplace) repo;
                };
                installLocation = "${config.home.homeDirectory}/.claude/plugins/marketplaces/${name}";
                lastUpdated = "1970-01-01T00:00:00.000Z"; # Managed by Nix, not runtime updates
              }
            )
            |> builtins.toJSON;

          # osgrep ships a SessionStart hook (hooks/start.js) that launches a
          # long-lived `osgrep serve` daemon. Its worker pool busy-loops at 100%
          # CPU once indexing finishes — four pegged cores, fans spun up — and it
          # runs uncapped, unlike our Nice'd/idle-IO osgrep-index.service. We
          # don't need it: the osgrep-index systemd timer already keeps every
          # allowlisted repo indexed. So, mirroring the mgrep treatment
          # (claudeMgrepDisableWatch below), we vendor the marketplace but neuter
          # its hooks.json. mgrep's hooks live in the WRITABLE plugin cache, so
          # that one is stripped at activation time; osgrep is served straight
          # from this read-only /nix/store symlink, so we can't edit it in place.
          # Instead we build a patched copy here (hooks.json → no-op) and symlink
          # THAT in. marketplace.src stays the raw input so findInputName (and
          # thus `claude-update-marketplaces`) keeps working.
          stripPluginHooks =
            name: src:
            pkgs.runCommand "claude-marketplace-${name}-nohooks" { } ''
              cp -r --no-preserve=mode,ownership ${src} "$out"
              echo '{ "hooks": {} }' > "$out/plugins/${name}/hooks.json"
            '';

          # Generate home.file entries for marketplace directories
          marketplaceFiles = lib.mapAttrs' (name: marketplace: {
            name = ".claude/plugins/marketplaces/${name}";
            value = {
              source = if name == "osgrep" then stripPluginHooks name marketplace.src else marketplace.src;
            };
          }) cfg.marketplaces;

          shared_exports = # sh
            ''
              export CLAUDE_CODE_DISABLE_FAST_MODE=1
              export CLAUDE_CONFIG_DIR="$HOME/.claude"
              export ENABLE_LSP_TOOL=0
            '';

          # Native binary wrapper
          claude-native = pkgs.writeShellScriptBin "claude-native" ''
            ${shared_exports}
            export PATH="${config.home.homeDirectory}/.local/bin:$PATH"
            exec ${pkgs.claude-code}/bin/claude "$@"
          '';

          # NPM-based binary wrapper (provides the claude-npm command name)
          claude-npm = pkgs.writeShellScriptBin "claude-npm" ''
            ${shared_exports}
            exec ${pkgs.claude-code-npm}/bin/claude "$@"
          '';

          # Main 'claude' command pointing to the selected version
          selectedClaude =
            if cfg.nativeInstall then
              {
                pkg = claude-native;
                bin = "claude-native";
              }
            else
              {
                pkg = claude-npm;
                bin = "claude-npm";
              };

          claude-package = pkgs.writeShellScriptBin "claude" ''
            exec ${selectedClaude.pkg}/bin/${selectedClaude.bin} "$@"
          '';

          claudeCarapaceSpec =
            pkgs.runCommand "claude-carapace-spec.yaml"
              {
                nativeBuildInputs = [ pkgs.nushell ];
                # claude-code is now a Bun-compiled Mach-O binary; its JIT
                # (MAP_JIT executable mappings) is SIGKILLed by the macOS
                # sandbox-exec profile. Run outside the chroot to scrape
                # `--help`. Linux's sandbox permits JIT, so keep it sandboxed
                # there (requires sandbox = "relaxed", set in modules/common.nix).
                __noChroot = pkgs.stdenv.isDarwin;
              }
              ''
                export HOME=$(mktemp -d)
                ${pkgs.claude-code}/bin/claude --help > help.txt
                nu ${./gen-carapace-spec.nu} help.txt > $out
              '';

          # Default plugin sync package (set via mkDefault below)
          defaultPluginSyncPackage = pkgs.writeNuApplication {
            name = "claude-plugin-sync";
            runtimeInputs = [ claude-package ];
            runtimeEnv = {
              CLAUDE_PLUGINS_CONFIG = "${config.dotFilesDir}/modules/claude/marketplaces.json";
            };
            text = builtins.readFile ./setup-plugins.nu;
          };

          pluginSyncExe = "${cfg.pluginSyncPackage}/bin/claude-plugin-sync";
        in
        {
          # Set the default for pluginSyncPackage (can be overridden by user)
          programs.claude.pluginSyncPackage = lib.mkDefault defaultPluginSyncPackage;

          # Core marketplaces. Registered here (not as an option `default`) so
          # feature modules can merge in their own — see modules/wakatime.nix.
          programs.claude.marketplaces = {
            "context-mode" = {
              repo = "mksglu/context-mode";
              src = inputs.claude-marketplace-context-mode;
            };
            "claude-plugins-official" = {
              repo = "anthropics/claude-plugins-official";
              src = inputs.claude-marketplace-official;
            };
            "outsmartly-plugins" = {
              repo = "outsmartly/claude-plugins";
              src = inputs.claude-marketplace-outsmartly;
            };
            "claude-code-lsps" = {
              repo = "Piebald-AI/claude-code-lsps";
              src = inputs.claude-marketplace-lsps;
            };
            "Mixedbread-Grep" = {
              repo = "mixedbread-ai/mgrep";
              src = inputs.claude-marketplace-mgrep;
            };
            "osgrep" = {
              repo = "Ryandonofrio3/osgrep";
              src = inputs.claude-marketplace-osgrep;
            };
            "ponytail" = {
              repo = "DietrichGebert/ponytail";
              src = inputs.claude-marketplace-ponytail;
            };
          };

          # MCP SSE client for connecting to the containerized proxy
          programs.mcp.enableProxy = true;

          # Single-hop out-of-store symlink for settings.json — see the note in
          # home.file. Runs after linkGeneration so it survives that phase
          # pruning the previously-managed symlink.
          home.activation.claudeSettingsSymlink = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
            ln -sfn "${config.dotFilesDir}/modules/claude/settings.json" \
              "${config.home.homeDirectory}/.claude/settings.json"
          '';

          # After claudeSettingsSymlink: `claude plugin install` writes
          # enabledPlugins to settings.json, which only succeeds once the
          # single-hop symlink is in place (see claudeSettingsSymlink).
          home.activation.claudePluginSync = lib.hm.dag.entryAfter [ "claudeSettingsSymlink" ] ''
            echo "Syncing claude plugins (background)..."
            ${pluginSyncExe} &>/dev/null &
            disown
          '';

          # Override plugin MCP configs to use the persistent proxy for instant startup.
          # This runs after plugin sync and rewrites .mcp.json in cached plugins to use
          # mcp-sse-client → proxy instead of slow direct remote connections.
          home.activation.claudePluginMcpOverride =
            lib.hm.dag.entryAfter [ "claudePluginSync" ] # sh
              ''
                _override_plugin_mcp() {
                  local cache_dir="${config.home.homeDirectory}/.claude/plugins/cache"
                  local proxy_url="${config.programs.mcp.proxyUrl}"

                  for dir in "$cache_dir"/outsmartly-plugins/dts/*/  "$cache_dir"/outsmartly-plugins/pts/*/ ; do
                    [ -d "$dir" ] || continue
                    local mcp_file="$dir/.mcp.json"
                    local plugin_name=$(basename "$(dirname "$(dirname "$dir")")")
                    local server_name=$(basename "$(dirname "$dir")")

                    # Map plugin directory name to proxy server name
                    local proxy_name=""
                    case "$server_name" in
                      dts) proxy_name="jira-d" ;;
                      pts) proxy_name="jira-p" ;;
                      *) continue ;;
                    esac

                    chmod u+w "$mcp_file" 2>/dev/null || true
                    cat > "$mcp_file" <<MCPEOF
                {
                  "mcpServers": {
                    "$proxy_name": {
                      "command": "mcp-sse-client",
                      "args": ["$proxy_url/servers/$proxy_name/sse", "--strip-capabilities", "resources"]
                    }
                  }
                }
                MCPEOF
                  done
                }
                _override_plugin_mcp
              '';

          # The mgrep plugin ships a SessionStart hook that runs `mgrep watch` in
          # every session's cwd — a recursive inotify watcher that exhausts
          # fs.inotify.max_user_watches across large repos and live-uploads
          # transient temp files. We keep the plugin (for its search skill) but
          # strip the hooks; indexing is handled by the mgrep-sync timer instead.
          home.activation.claudeMgrepDisableWatch =
            lib.hm.dag.entryAfter [ "claudePluginSync" ] # sh
              ''
                for hookfile in "${config.home.homeDirectory}"/.claude/plugins/cache/Mixedbread-Grep/mgrep/*/hooks/hook.json; do
                  [ -f "$hookfile" ] || continue
                  chmod u+w "$hookfile" 2>/dev/null || true
                  echo '{ "hooks": {} }' > "$hookfile"
                done
              '';

          home.packages = [
            claude-package
            claude-native
            claude-npm
            cfg.pluginSyncPackage
            updateMarketplacesPackage
          ]
          ++ lib.optionals pkgs.stdenv.isLinux [
            pkgs.pkgs-mine.claude-yolo
            pkgs.pkgs-mine.claude-overlay
          ];

          # Carapace flag/subcommand completions, generated from `claude --help`.
          # (--resume values are served natively in nushell; see nushell config.)
          xdg.configFile."carapace/specs/claude.yaml" = lib.mkIf config.programs.carapace.enable {
            source = claudeCarapaceSpec;
          };

          home.file = {
            ".local/bin/claude".source = "${claude-package}/bin/claude";
            # settings.json is symlinked via an activation script below, not
            # here: `claude plugin install` atomically rewrites enabledPlugins
            # (tmp + rename beside the target), and mkOutOfStoreSymlink routes
            # through the read-only home-files store aggregate — a second hop
            # that lands the tmp in /nix/store → EROFS. A direct single-hop
            # symlink keeps the tmp in modules/claude/ (writable), so installs
            # succeed and write enablement back into the tracked repo file.
            ".claude/keybindings.json".source =
              config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/modules/claude/keybindings.json";
            # Library modules — sourced via `use ~/.claude/lib-*.nu` from the
            # hook wrappers, so they run under the same pinned nushell and need
            # no wrapper of their own. Kept live-editable.
            ".claude/lib-transcript.nu".source =
              config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/modules/claude/lib-transcript.nu";
            ".claude/lib-focus.nu".source =
              config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/modules/claude/lib-focus.nu";
            ".claude/schemas/edit-hooks.schema.json".source =
              config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/modules/claude/edit-hooks.schema.json";
            ".claude/marketplaces.json".source =
              config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/modules/claude/marketplaces.json";
            ".claude/setup-plugins.nu".source =
              config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/modules/claude/setup-plugins.nu";
            ".mcp.json".text = builtins.toJSON {
              mcpServers = {
                executor = {
                  type = "http";
                  url = "https://executor.lalala.casa/mcp";
                };
              };
            };
            # Global mgrep defaults. Per-repo .mgreprc.yaml overrides these.
            # Raised from the 1000-file default so the dedicated worktrees
            # (~1.4k tracked files) are not silently truncated on sync.
            ".config/mgrep/config.yaml".text = ''
              maxFileCount: 5000
            '';
            ".claude/agents".source =
              config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/modules/claude/agents";
            ".claude/commands".source =
              config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/modules/claude/commands";
            ".claude/CLAUDE.md".source =
              config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/modules/claude/CLAUDE.md";
            ".claude/plugins/known_marketplaces.json".text = knownMarketplacesJson;
            # tmux-claude-resurrect Claude hooks: thin execs that point at the
            # plugin's bash scripts.  Direct symlinks won't work because the
            # hook scripts source a sibling `lib-claude-pid.sh` via
            # `dirname "${BASH_SOURCE[0]}"`, so we need BASH_SOURCE[0] to resolve
            # to the /nix/store hooks directory.
            ".claude/tmux-assistant-claude-track.sh" = {
              text = ''
                #!/usr/bin/env bash
                exec ${pkgs.pkgs-mine.tmux-claude-resurrect}/share/tmux-plugins/tmux-assistant-resurrect/hooks/claude-session-track.sh "$@"
              '';
              executable = true;
            };
            ".claude/tmux-assistant-claude-cleanup.sh" = {
              text = ''
                #!/usr/bin/env bash
                exec ${pkgs.pkgs-mine.tmux-claude-resurrect}/share/tmux-plugins/tmux-assistant-resurrect/hooks/claude-session-cleanup.sh "$@"
              '';
              executable = true;
            };
          }
          # Nushell hook scripts: each gets a live-editable .nu plus a store
          # wrapper (~/.claude/<name>) that pins the interpreter. settings.json
          # invokes the wrapper, never the raw .nu.
          // (mkNuHook "notify")
          // (mkNuHook "notify-if-question")
          // (mkNuHook "record-pending-tool")
          // (mkNuHook "format-and-lint")
          // (mkNuHook "tmux-claude-indicator")
          // (mkNuHook "statusline")
          // marketplaceFiles;

          # Daily update check for claude-code sources
          services.scheduled.claude-code-update = {
            description = "Check for claude-code updates";
            command = "${claude-code-update}/bin/claude-code-update";
            workingDirectory = "${config.dotFilesDir}/packages/claude-code";
            calendar = "daily";
            hour = 9;
            minute = 0;
          };

          # Daily plugin sync - ensures marketplaces and plugins are installed
          services.scheduled.claude-plugin-sync = {
            description = "Sync Claude Code marketplaces and plugins";
            command = pluginSyncExe;
            calendar = "daily";
            hour = 9;
            minute = 0;
          };
        }
      );
    };
}
