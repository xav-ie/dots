{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.services.local-networking) baseDomain caCertFile;
  cfg = config.services.mcp-proxy;
  subdomain = "mcp";
  fullHostName = "${subdomain}.${baseDomain}";
  containerPort = 18199;

  # ── Submodule type for individual MCP servers ────────────────────────
  serverOpts = {
    options = {
      command = lib.mkOption {
        type = lib.types.str;
        description = "Command to start the MCP server";
      };
      args = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Arguments to pass to the command";
      };
      packages = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = [ ];
        description = "Packages to include in the OCI image for this server";
      };
      extraHosts = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Extra --add-host entries for the container (e.g. 'hostname:host-gateway')";
      };
      secretEnvVars = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Env vars from sops secrets (key = env var name, value = sops path)";
        example = {
          MY_TOKEN = "path/to/secret";
        };
      };
      envVars = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Plain (non-secret) env vars for this server";
      };
    };
  };

  # ── Collect from all server submodules ───────────────────────────────
  allServers = cfg.servers;
  serverValues = lib.attrValues allServers;

  allPackages = lib.unique (lib.concatMap (s: s.packages) serverValues);
  allExtraHosts = lib.unique (lib.concatMap (s: s.extraHosts) serverValues);
  allSecretEnvVars = lib.foldl (a: s: a // s.secretEnvVars) { } serverValues;
  allEnvVars = lib.foldl (a: s: a // s.envVars) { } serverValues;

  # ── Combined CA bundle ──────────────────────────────────────────────
  combinedCACert = pkgs.runCommand "combined-ca-certs" { } ''
    mkdir -p $out/etc/ssl/certs
    cat ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt ${caCertFile} \
      > $out/etc/ssl/certs/ca-bundle.crt
  '';

  # ── mcp-proxy server configuration JSON ─────────────────────────────
  proxyServersConfig = pkgs.writeText "mcp-proxy-servers.json" (
    builtins.toJSON {
      mcpServers = lib.mapAttrs (_: s: {
        inherit (s) command args;
      }) allServers;
    }
  );

  # ── OCI image ───────────────────────────────────────────────────────
  mcp-proxy-image = pkgs.dockerTools.buildLayeredImage {
    name = "mcp-proxy";
    tag = "latest";

    contents = [
      pkgs.mcp-proxy
      pkgs.coreutils
      combinedCACert
    ]
    ++ allPackages;

    extraCommands = ''
      mkdir -p etc
      cp ${proxyServersConfig} etc/mcp-proxy-servers.json
    '';

    config = {
      Cmd = [
        "${pkgs.mcp-proxy}/bin/mcp-proxy"
        "--host"
        "0.0.0.0"
        "--port"
        (toString containerPort)
        "--pass-environment"
        "--named-server-config"
        "/etc/mcp-proxy-servers.json"
      ];
      ExposedPorts."${toString containerPort}/tcp" = { };
      Env = [
        "HOME=/tmp"
        "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
        "NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-bundle.crt"
      ];
    };
  };

  # ── Sops env file content ───────────────────────────────────────────
  envFileContent =
    let
      secretLines = lib.mapAttrsToList (
        name: sopsPath: "${name}=${config.sops.placeholder.${sopsPath}}"
      ) allSecretEnvVars;
      plainLines = lib.mapAttrsToList (name: value: "${name}=${value}") allEnvVars;
    in
    lib.concatStringsSep "\n" (secretLines ++ plainLines);
in
{
  imports = [
    ./servers/slack.nix
    ./servers/nixos.nix
    ./servers/chrome-devtools.nix
    ./servers/jira-delivery.nix
    ./servers/jira-projects.nix
  ];

  options.services.mcp-proxy = {
    servers = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule serverOpts);
      default = { };
      description = "MCP servers to run inside the containerized proxy";
    };
  };

  config = {
    services.local-networking.subdomains = [ subdomain ];

    # ── Sops secrets → container env file ──────────────────────────────
    sops.templates."mcp-proxy-env" = {
      content = envFileContent;
      mode = "0400";
      restartUnits = [ "podman-${subdomain}.service" ];
    };

    # ── Container definition ───────────────────────────────────────────
    virtualisation.oci-containers.containers.${subdomain} = {
      autoStart = true;
      imageFile = mcp-proxy-image;
      image = "mcp-proxy:latest";
      environmentFiles = [
        config.sops.templates."mcp-proxy-env".path
      ];
      extraOptions = map (h: "--add-host=${h}") allExtraHosts;
      labels = {
        "traefik.enable" = "true";
        "traefik.http.routers.${subdomain}-secure.entrypoints" = "websecure";
        "traefik.http.routers.${subdomain}-secure.rule" = "Host(`${fullHostName}`)";
        "traefik.http.routers.${subdomain}-secure.tls" = "true";
        "traefik.http.routers.${subdomain}-secure.tls.certResolver" = "cloudflare";
        "traefik.http.routers.${subdomain}-secure.service" = "${subdomain}-svc";
        "traefik.http.services.${subdomain}-svc.loadbalancer.server.port" = toString containerPort;
      };
    };
  };
}
