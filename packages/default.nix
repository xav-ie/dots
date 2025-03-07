# Based on:
# https://github.com/Misterio77/nix-config/blob/e360a9ecf6de7158bea813fc075f3f6228fc8fc0/pkgs/default.nix
{ lib, pkgs }:
let
  optionalAttrs = bool: attrSet: if bool then attrSet else { };
  writeNuApplication = import ../lib/writeNuApplication { inherit lib pkgs; };
  notify = pkgs.callPackage ./notify { };
in
rec {
  default = pkgs.callPackage ./cache-command { };

  # Personal scripts
  apple-emoji-linux = pkgs.callPackage ./apple-emoji-linux { };
  cache-command = pkgs.callPackage ./cache-command { };
  ff = pkgs.callPackage ./ff { };
  # g = pkgs.callPackage ./g { };
  j = pkgs.callPackage ./j { };
  jira-task-list = pkgs.callPackage ./jira-task-list { inherit cache-command; };
  jira-list = pkgs.callPackage ./jira-list { inherit cache-command; };
  nvim = pkgs.callPackage ./nvim { };
  inherit notify;
  is-sshed = pkgs.callPackage ./is-sshed { };
  searcher = pkgs.callPackage ./searcher { inherit writeNuApplication; };
  tmux-tab-name-update = pkgs.callPackage ./tmux-tab-name-update { };
  uair-toggle-and-notify = pkgs.callPackage ./uair-toggle-and-notify { inherit notify; };
  zellij-tab-name-update = pkgs.callPackage ./zellij-tab-name-update { };
}
// (optionalAttrs pkgs.stdenv.isDarwin {
  fix-yabai = pkgs.callPackage ./fix-yabai { };
  focus-or-open-application = pkgs.callPackage ./focus-or-open-application {
    inherit writeNuApplication notify;
  };
  move-pip = pkgs.callPackage ./move-pip { inherit writeNuApplication; };
})
// (optionalAttrs pkgs.stdenv.isLinux {
  move-active = pkgs.callPackage ./move-active { };
  openrgb-appimage = pkgs.callPackage ./openrgb-appimage { };
  record = pkgs.callPackage ./record { };
  record-section = pkgs.callPackage ./record-section { };
})
