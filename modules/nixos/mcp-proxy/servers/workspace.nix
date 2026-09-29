{
  flake.modules.nixos.praesidium =
    { lib, pkgs, ... }:
    let
      inherit (pkgs.pkgs-mine) workspace-mcp;
      # One Google account per workspace-mcp instance, each with its own token
      # store at /var/lib/workspace-<account>.
      accounts = [
        "personal"
        "work"
      ];
      hostDir = account: "/var/lib/workspace-${account}";
      stateDir = account: "/data-${account}";
    in
    {
      systemd.tmpfiles.rules = accounts |> map (account: "d ${hostDir account} 0700 root root -");

      services.mcp-proxy.servers = lib.listToAttrs (
        map (
          account:
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
            volumes = [ "${hostDir account}:${stateDir account}" ];
            # The token store is salted with hostname + username, so it can only be
            # read back by the same identity that wrote it. Log in from inside this
            # container, not the host:
            #   podman exec -it mcp workspace-<account> login
            # keytar isn't in the image; skip the probe and go straight to the
            # encrypted file in the state dir.
            envVars.GEMINI_CLI_WORKSPACE_FORCE_FILE_STORAGE = "true";
          }
        ) accounts
      );

      # One endpoint for every account: /servers/workspace/ picks the backend
      # by the `Account` header (see headerRoutes in ../mcp-proxy.nix).
      services.mcp-proxy.headerRoutes.workspace = lib.genAttrs accounts (account: "workspace-${account}");
    };
}
