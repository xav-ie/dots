# WakaTime, in one place.
#
# WakaTime tracks coding time across every integration that reads the shared
# ~/.wakatime.cfg: the VS Code extension (modules/home-darwin/vscode.nix), the
# macOS menu-bar app (the cask below), and the Claude Code plugin
# (claude-code-wakatime, wired in modules/claude). This file owns everything
# WakaTime needs *except* those integrations' own enable lines:
#   - the sops-managed API key (declared here, decrypted per-host),
#   - the ~/.wakatime.cfg the key is rendered into,
#   - the pinned wakatime-cli on PATH (packages/wakatime-cli), and
#   - the macOS cask + its Accessibility grant.
#
# Dendritic: one file, several aggregates. The key + activation reach both
# platforms; the cask + TCC grant are darwin-only.
#
# The key is sops-managed rather than written into any Nix-store file (the store
# is world-readable). It's the *same* `wakapi/api_key` the self-hosted backend
# (modules/nixos/wakapi.nix) seeds its account with, so the clients authenticate
# against our own instance. Add it once with `sops secrets/main.yaml`:
#   wakapi:
#     api_key: <a uuid>
# then `just system`.
let
  # Same reach as sops-common (darwin.macos + nixos.linux): the home activation
  # below runs in homeManager.common on both nox and praesidium and reads this
  # secret's path at eval time, so it must be declared on each. On praesidium
  # wakapi.nix additionally grants its seed group-read of the same secret.
  keySecret = config: {
    "wakapi/api_key" = {
      owner = config.defaultUser;
      mode = "0400";
    };
  };
in
{
  flake.modules.darwin.macos =
    { config, ... }:
    {
      sops.secrets = keySecret config;

      homebrew.casks = [ "wakatime" ];

      security.tcc.apps = [
        {
          # WakaTime menu-bar app (wakatime/macos-wakatime cask). Needs
          # Accessibility to observe the frontmost app/window for system-wide
          # time tracking. Ships a Developer ID seal and its bundle isn't
          # mutated, so a plain bundle-id grant is enough (no re-sign/csreq pin).
          bundleId = "macos-wakatime.WakaTime";
          services = [ "Accessibility" ];
        }
      ];
    };

  flake.modules.nixos.linux =
    { config, ... }:
    {
      sops.secrets = keySecret config;
    };

  # The VS Code extension. `programs.vscode.profiles.default.extensions` is a
  # list option, so this merges into the set built in modules/home-darwin/
  # vscode.nix — no need to touch that file's local pkg bindings. Pulled from the
  # same nix-vscode-extensions marketplace it uses (free extension, so none of
  # vscode.nix's unfree plumbing is needed).
  flake.modules.homeManager.darwin =
    { pkgs, inputs, ... }:
    {
      programs.vscode.profiles.default.extensions = [
        inputs.nix-vscode-extensions.extensions.${pkgs.stdenv.hostPlatform.system}.vscode-marketplace.wakatime.vscode-wakatime
      ];
    };

  flake.modules.homeManager.common =
    {
      lib,
      osConfig,
      inputs,
      pkgs,
      ...
    }:
    {
      # Pin wakatime-cli on PATH. Every WakaTime integration prefers a `which
      # wakatime-cli` hit over its own bundled/downloaded copy — and the Claude
      # plugin treats a PATH binary as always-current — so this keeps the CLI
      # reproducible and stops the self-download into ~/.wakatime. Needed at all
      # because nixpkgs' wakatime-cli is too old for `--sync-ai-activity`.
      home.packages = [ pkgs.pkgs-mine.wakatime-cli ];

      # Claude Code plugin marketplace. Merges into the core set registered in
      # modules/claude/claude.nix (mergeable attrsOf option). The plugin itself
      # is enabled in the hand-edited marketplaces.json / settings.json.
      programs.claude.marketplaces.wakatime = {
        repo = "wakatime/claude-code-wakatime";
        src = inputs.claude-marketplace-wakatime;
      };

      # Render the key into ~/.wakatime.cfg, only (re)writing when missing/changed
      # so WakaTime can keep appending its own [internal] state and the file stays
      # user-writable.
      home.activation.wakatimeApiKey =
        lib.hm.dag.entryAfter [ "writeBoundary" ] # sh
          ''
            keyfile=${lib.escapeShellArg osConfig.sops.secrets."wakapi/api_key".path}
            api_url="https://wakapi.lalala.casa/api"
            cfg="$HOME/.wakatime.cfg"
            if [ -r "$keyfile" ]; then
              key="$(cat "$keyfile")"
              if [ ! -f "$cfg" ] || ! grep -qF "$key" "$cfg" || ! grep -qF "$api_url" "$cfg"; then
                run printf '[settings]\napi_key = %s\napi_url = %s\n' "$key" "$api_url" > "$cfg"
                run chmod 600 "$cfg"
              fi
            else
              echo "wakatime: $keyfile not readable yet — add the key to secrets/main.yaml, then 'just system'"
            fi
          '';
    };
}
