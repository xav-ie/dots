{
  flake.modules.nixos.praesidium =
    { pkgs, ... }:
    let
      inherit (pkgs.pkgs-mine) workspace-mcp;
      stateDir = "/var/lib/workspace-mcp";
    in
    {
      systemd.tmpfiles.rules = [ "d ${stateDir} 0700 root root -" ];

      services.mcp-proxy.servers.workspace = {
        command = "${workspace-mcp}/bin/workspace-mcp";
        # fakeNss supplies /etc/passwd: the token store salts its encryption key
        # with os.userInfo(), which throws ENOENT when root has no passwd entry.
        packages = [
          pkgs.dockerTools.fakeNss
          workspace-mcp
        ];
        volumes = [ "${stateDir}:/data" ];
        envVars = {
          # The token store is salted with hostname + username, so it can only be
          # read back by the same identity that wrote it. Log in from inside this
          # container (`podman exec -it mcp workspace-mcp login`), not the host.
          WORKSPACE_MCP_STATE_DIR = "/data";
          # keytar isn't in the image; skip the probe and go straight to the
          # encrypted file in /data.
          GEMINI_CLI_WORKSPACE_FORCE_FILE_STORAGE = "true";
        };
      };
    };
}
