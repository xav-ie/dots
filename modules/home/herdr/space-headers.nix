# Folder-style grouping in the agent sidebar: the space name appears once, above
# its first agent, instead of on every entry. herdr has no such layout, but it
# drops sidebar rows whose tokens resolve to nothing, so a `$space_header` row
# plus a tagger service produces the same result — see packages/herdr-space-headers.
{
  flake.modules.homeManager.linux =
    { pkgs, lib, ... }:
    {
      systemd.user.services.herdr-space-headers = {
        Unit = {
          Description = "Tag the first agent of each herdr space for the sidebar header row";
          # No socket to wait on: the tagger tolerates herdr being absent and
          # retries on its own interval.
          After = [ "default.target" ];
        };
        Service = {
          ExecStart = lib.getExe pkgs.pkgs-mine.herdr-space-headers;
          Environment = [ "PATH=${lib.makeBinPath [ pkgs.herdr ]}" ];
          Restart = "always";
          RestartSec = 10;
        };
        Install.WantedBy = [ "default.target" ];
      };
    };
}
