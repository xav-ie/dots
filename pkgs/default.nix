# Stolen from:
# https://github.com/Misterio77/nix-config/blob/e360a9ecf6de7158bea813fc075f3f6228fc8fc0/pkgs/default.nix
# TODO: go through all commented packages and see how they are implemented
{ pkgs, ... }:
rec {
  # Packages with an actual source
  # rgbdaemon = pkgs.callPackage ./rgbdaemon { };
  # shellcolord = pkgs.callPackage ./shellcolord { };
  # trekscii = pkgs.callPackage ./trekscii { };
  default = pkgs.callPackage ./cache-command { };

  # Personal scripts
  cache-command = pkgs.callPackage ./cache-command { };
  ff = pkgs.callPackage ./ff { };
  fix-yabai = pkgs.callPackage ./fix-yabai { };
  # g = pkgs.callPackage ./g { };
  j = pkgs.callPackage ./j { };
  jira-task-list = pkgs.callPackage ./jira-task-list { inherit cache-command; };
  jira-list = pkgs.callPackage ./jira-list { inherit cache-command; };
  notify = pkgs.callPackage ./notify { };
  nvim = pkgs.callPackage ./nvim { };
  is-sshed = pkgs.callPackage ./is-sshed { };
  # record = pkgs.callPackage ./record { };
  # record-section = pkgs.callPackage ./record-section { };
  searcher = pkgs.callPackage ./searcher { };
  uair-toggle-and-notify = pkgs.callPackage ./uair-toggle-and-notify { inherit notify; };
  zellij-tab-name-update = pkgs.callPackage ./zellij-tab-name-update { };
  # nix-inspect = pkgs.callPackage ./nix-inspect { };
  # minicava = pkgs.callPackage ./minicava { };
  # pass-wofi = pkgs.callPackage ./pass-wofi { };
  # primary-xwayland = pkgs.callPackage ./primary-xwayland { };
  # wl-mirror-pick = pkgs.callPackage ./wl-mirror-pick { };
  # lyrics = pkgs.python3Packages.callPackage ./lyrics { };
  # xpo = pkgs.callPackage ./xpo { };
  # tly = pkgs.callPackage ./tly { };
  # hyprslurp = pkgs.callPackage ./hyprslurp { };

  # My slightly customized plymouth theme, just makes the blue outline white
  # plymouth-spinner-monochrome = pkgs.callPackage ./plymouth-spinner-monochrome { };

  # My wallpaper collection
  # wallpapers = pkgs.callPackage ./wallpapers { };
}
