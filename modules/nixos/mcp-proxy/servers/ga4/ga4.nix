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

      # The container has no ADC. google-auth reads the authorized_user JSON
      # written to the volume by `ga4-login` (see login.py) — analytics-mcp
      # calls google.auth.default(scopes=[analytics.readonly]) and refreshes
      # the token itself, so nothing but the creds file is needed at runtime.
      ga4-mcp = pkgs.writeShellApplication {
        name = "ga4-mcp";
        text = ''
          creds="''${GA4_CREDS_FILE:-/data-ga4/creds.json}"
          if [ ! -s "$creds" ]; then
            echo "ga4-mcp: $creds missing or empty — run: podman exec -it mcp ga4-login" >&2
          fi
          export GOOGLE_APPLICATION_CREDENTIALS="$creds"
          exec "${venv}/bin/analytics-mcp" "$@"
        '';
      };

      # Interactive consent flow, workspace-<account>-login style:
      #   podman exec -it mcp ga4-login
      # Uses the gtm/* sops env (same desktop OAuth client) and writes the
      # authorized_user JSON into the server volume.
      ga4-login = pkgs.writeShellApplication {
        name = "ga4-login";
        runtimeInputs = [ venv ];
        text = ''
          exec "${venv}/bin/python" "${./login.py}" "$@"
        '';
      };
    in
    {
      packages = {
        inherit ga4-mcp ga4-login;
      };
    };

  flake.modules.nixos.praesidium =
    { pkgs, ... }:
    let
      inherit (pkgs.pkgs-mine) ga4-mcp ga4-login;
      stateDir = "/data-ga4";
    in
    {
      systemd.tmpfiles.rules = [ "d /var/lib/ga4 0700 root root -" ];

      services.mcp-proxy.servers.ga4 = {
        command = "${ga4-mcp}/bin/ga4-mcp";
        packages = [
          ga4-mcp
          ga4-login
        ];
        volumes = [ "/var/lib/ga4:${stateDir}" ];
        # Same outsmartly-app desktop client as the gtm server — reusing its
        # sops keys means no new secrets to mint; only the consent (which
        # scopes the refresh token to analytics.readonly) happens in-container.
        secretEnvVars = {
          GA4_CLIENT_ID = "gtm/client_id";
          GA4_CLIENT_SECRET = "gtm/client_secret";
        };
      };
    };
}
