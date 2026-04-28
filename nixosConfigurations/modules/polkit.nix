{ pkgs, ... }:
{
  security.polkit.enable = true;

  # `/run/polkit-1/rules.d` is in polkit's hardcoded rules-dir search
  # path. The directory only exists if something pre-creates it, and
  # polkit logs "Error opening rules directory" every reload otherwise.
  systemd.tmpfiles.rules = [
    "d /run/polkit-1/rules.d 0755 root root -"
  ];

  # The other path polkit probes — `/usr/local/share/polkit-1/rules.d` —
  # is hardcoded and doesn't exist on NixOS. Drop only that exact line;
  # real polkit errors at other paths still log.
  systemd.services.polkit.serviceConfig.LogFilterPatterns = [
    "~Error opening rules directory:.*usr/local/share/polkit-1"
  ];

  # GUI password-prompt agent for polkit. Started per-user in the
  # graphical session so apps (gparted, file managers, etc.) can ask
  # for elevation through a Wayland-friendly dialog.
  systemd.user.services.polkit-gnome-authentication-agent-1 = {
    description = "polkit-gnome-authentication-agent-1";
    wantedBy = [ "graphical-session.target" ];
    wants = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
      Restart = "on-failure";
      RestartSec = 1;
      TimeoutStopSec = 10;
    };
  };
}
