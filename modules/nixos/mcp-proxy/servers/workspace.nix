{
  flake.modules.nixos.praesidium =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (pkgs.pkgs-mine) workspace-mcp;
      # One Google account per workspace-mcp instance: each gets its own token
      # store. account -> host state dir.
      accounts = {
        personal = "/var/lib/workspace-mcp"; # xruizify@gmail.com
        work = "/var/lib/workspace-work"; # xavier@outsmartly.com
      };
      stateDir = account: "/data-${account}";
    in
    {
      systemd.tmpfiles.rules = lib.attrValues accounts |> map (d: "d ${d} 0700 root root -");

      services.mcp-proxy.servers = lib.mapAttrs' (
        account: hostDir:
        let
          name = "workspace-${account}";
          # envVars are container-wide (merged across servers), so the
          # per-account state dir is set in a wrapper instead.
          launcher = pkgs.writeShellScriptBin name ''
            WORKSPACE_MCP_STATE_DIR=${stateDir account} exec ${workspace-mcp}/bin/workspace-mcp "$@"
          '';
        in
        lib.nameValuePair name {
          command = "${launcher}/bin/${name}";
          # fakeNss supplies /etc/passwd: the token store salts its encryption key
          # with os.userInfo(), which throws ENOENT when root has no passwd entry.
          packages = [
            pkgs.dockerTools.fakeNss
            launcher
          ];
          volumes = [ "${hostDir}:${stateDir account}" ];
          # The token store is salted with hostname + username, so it can only be
          # read back by the same identity that wrote it. Log in from inside this
          # container, not the host:
          #   podman exec -it mcp workspace-<account> login
          # keytar isn't in the image; skip the probe and go straight to the
          # encrypted file in the state dir.
          envVars.GEMINI_CLI_WORKSPACE_FORCE_FILE_STORAGE = "true";
        }
      ) accounts;

      # One endpoint for every account: /servers/workspace/ is routed to
      # workspace-<account> by the `Account` request header, so executor holds a
      # single integration with one connection (header value) per Google account.
      # No header matches no router → 404, rather than a silent default account.
      virtualisation.oci-containers.containers.mcp.labels = lib.concatMapAttrs (
        account: _:
        let
          r = "workspace-${account}";
        in
        {
          "traefik.http.routers.${r}.entrypoints" = "websecure";
          "traefik.http.routers.${r}.rule" =
            "Host(`mcp.${config.services.local-networking.baseDomain}`) && PathPrefix(`/servers/workspace/`) && Header(`Account`, `${account}`)";
          "traefik.http.routers.${r}.tls" = "true";
          "traefik.http.routers.${r}.tls.certResolver" = "cloudflare";
          "traefik.http.routers.${r}.service" = "mcp-svc";
          "traefik.http.routers.${r}.middlewares" = r;
          "traefik.http.middlewares.${r}.replacepathregex.regex" = "^/servers/workspace/(.*)";
          "traefik.http.middlewares.${r}.replacepathregex.replacement" = "/servers/${r}/$1";
        }
      ) accounts;
    };
}
