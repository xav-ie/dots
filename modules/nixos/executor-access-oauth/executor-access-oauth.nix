{
  flake.modules.nixos.praesidium =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.executor-access-oauth;
      executor = config.services.executor;
      middleware = "executor-access-oauth";
      verifier = pkgs.writers.writePython3Bin "executor-access-oauth" {
        libraries = [
          pkgs.python3Packages.pyjwt
        ]
        ++ pkgs.python3Packages.pyjwt.optional-dependencies.crypto;
        flakeIgnore = [ "E501" ];
      } (builtins.readFile ./verifier.py);
    in
    {
      options.services.executor-access-oauth = {
        enable = lib.mkEnableOption "Cloudflare Access OAuth sign in for executor's /mcp" // {
          default = executor.enable;
        };
        port = lib.mkOption {
          type = lib.types.port;
          default = 38975;
          description = "Loopback port of the forwardAuth verifier.";
        };
      };

      # OAuth only MCP clients (Gemini) sign in through Access Managed OAuth on
      # the /mcp Access app and reach executor with an Access assertion instead
      # of executor's bearer. This route swaps one for the other in traefik.
      config = lib.mkIf cfg.enable {
        services.local-networking = {
          middlewares.${middleware}.forwardAuth = {
            address = "http://127.0.0.1:${toString cfg.port}";
            authRequestHeaders = [
              "Authorization"
              "Cf-Access-Jwt-Assertion"
            ];
            authResponseHeaders = [ "Authorization" ];
          };
          proxies.executor-mcp = {
            inherit (executor) port subdomain;
            rule = "Host(`${executor.subdomain}.${config.services.local-networking.baseDomain}`) && PathPrefix(`/mcp`)";
            priority = 100;
            middlewares = [ middleware ];
          };
        };

        # The team domain and the /mcp app's AUD tag name the Cloudflare
        # account, so they stay in sops rather than in this file.
        sops.secrets = {
          "executor-access-aud" = {
            sopsFile = ../../../secrets/executor-v2.yaml;
            key = "access_mcp_aud";
          };
          "executor-access-team-domain" = {
            sopsFile = ../../../secrets/executor-v2.yaml;
            key = "access_team_domain";
          };
        };

        sops.templates."executor-access-oauth.env" = {
          owner = config.defaultUser;
          content = ''
            CF_ACCESS_AUD=${config.sops.placeholder."executor-access-aud"}
            CF_ACCESS_TEAM_DOMAIN=${config.sops.placeholder."executor-access-team-domain"}
          '';
          restartUnits = [ "executor-access-oauth.service" ];
        };

        systemd.services.executor-access-oauth = {
          description = "Cloudflare Access assertion to executor bearer for /mcp";
          wantedBy = [ "multi-user.target" ];
          after = [
            "network-online.target"
            "sops-install-secrets.service"
          ];
          wants = [ "network-online.target" ];
          environment = {
            # The bearer is the EXECUTOR_AUTH_TOKEN line of the
            # runtime-decrypted shell-env, as for executor itself.
            EXECUTOR_ENV_FILE = "/run/secrets/shell-env";
            PORT = toString cfg.port;
            SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
          };
          serviceConfig = {
            User = config.defaultUser;
            EnvironmentFile = config.sops.templates."executor-access-oauth.env".path;
            ExecStart = lib.getExe verifier;
            Restart = "on-failure";
            RestartSec = 5;
          };
        };
      };
    };
}
