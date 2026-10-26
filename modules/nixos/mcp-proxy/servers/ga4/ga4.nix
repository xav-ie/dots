{
  inputs,
  ...
}:
{
  # Colocated like gtm: the uv workspace (pyproject.toml + uv.lock) pins
  # analytics-mcp 0.8.0 and its whole tree; uv2nix builds a sealed venv from
  # the lockfile (wheel-preferring, so grpcio/pydantic-core & co. come as
  # manylinux wheels instead of source builds). Re-lock with the nixpkgs uv:
  #   /nix/store/373m9zapp9af30wim3d9i553fxyap7qz-uv-0.13.0/bin/uv lock
  perSystem =
    {
      pkgs,
      lib,
      writeNuApplication,
      ...
    }:
    let
      workspace = inputs.uv2nix.lib.workspace.loadWorkspace { workspaceRoot = ./.; };

      overlay = workspace.mkPyprojectOverlay {
        sourcePreference = "wheel";
      };

      pythonSet =
        (pkgs.callPackage inputs.pyproject-nix.build.packages {
          python = pkgs.python3;
        }).overrideScope
          (
            lib.composeManyExtensions [
              inputs.pyproject-build-systems.overlays.wheel
              overlay
            ]
          );

      venv = pythonSet.mkVirtualEnv "ga4-mcp-env" workspace.deps.default;

      # The container has no ADC. Assemble an authorized_user credential from
      # the GA4_* sops env vars and point google-auth at it — analytics-mcp
      # calls google.auth.default(scopes=[analytics.readonly]), and a refresh
      # token minted for that scope (ga4-mcp-auth) refreshes correctly. The
      # values are URL-safe OAuth strings, so printf-JSON needs no escaping.
      ga4-mcp = pkgs.writeShellApplication {
        name = "ga4-mcp";
        text = ''
          if [ -z "''${GA4_CLIENT_ID:-}" ] || [ -z "''${GA4_CLIENT_SECRET:-}" ] || [ -z "''${GA4_REFRESH_TOKEN:-}" ]; then
            echo "ga4-mcp: GA4_CLIENT_ID/GA4_CLIENT_SECRET/GA4_REFRESH_TOKEN not set — run ga4-mcp-auth and sops set (see servers/ga4/auth.nu)" >&2
          fi
          creds="$(mktemp)"
          trap 'rm -f "$creds"' EXIT
          export GOOGLE_APPLICATION_CREDENTIALS="$creds"
          printf '{"type":"authorized_user","client_id":"%s","client_secret":"%s","refresh_token":"%s"}' \
            "''${GA4_CLIENT_ID:-}" "''${GA4_CLIENT_SECRET:-}" "''${GA4_REFRESH_TOKEN:-}" > "$creds"
          exec "${venv}/bin/analytics-mcp" "$@"
        '';
      };

      # One-off credential minter, same oauth2l flow as gtm's (see auth.nu).
      ga4-mcp-auth = writeNuApplication {
        name = "ga4-mcp-auth";
        runtimeInputs = [ pkgs.oauth2l ];
        text = builtins.readFile ./auth.nu;
      };
    in
    {
      packages = {
        inherit ga4-mcp ga4-mcp-auth;
      };
    };

  flake.modules.nixos.praesidium =
    { pkgs, ... }:
    let
      inherit (pkgs.pkgs-mine) ga4-mcp;
    in
    {
      services.mcp-proxy.servers.ga4 = {
        command = "${ga4-mcp}/bin/ga4-mcp";
        packages = [ ga4-mcp ];
        secretEnvVars = {
          GA4_CLIENT_ID = "ga4/client_id";
          GA4_CLIENT_SECRET = "ga4/client_secret";
          GA4_REFRESH_TOKEN = "ga4/refresh_token";
        };
      };
    };
}
