{
  flake.modules.nixos.praesidium =
    { pkgs, ... }:
    let
      dataDir = "/var/lib/tasks-mcp";
      server = pkgs.writers.writePython3Bin "tasks-mcp" {
        libraries = [ pkgs.python3Packages.mcp ];
        flakeIgnore = [ "E501" ];
      } (builtins.readFile ./server.py);
    in
    {
      systemd.tmpfiles.rules = [ "d ${dataDir} 0700 root root -" ];

      services.mcp-proxy.servers.tasks = {
        command = "${server}/bin/tasks-mcp";
        packages = [ server ];
        envVars.TASKS_DB = "/data/tasks/tasks.db";
        volumes = [ "${dataDir}:/data/tasks" ];
      };
    };
}
