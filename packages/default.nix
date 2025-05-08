# Based on:
# https://github.com/Misterio77/nix-config/blob/e360a9ecf6de7158bea813fc075f3f6228fc8fc0/pkgs/default.nix
{
  lib,
  pkgs,
  generate-kaomoji,
}:
let
  optionalAttrs = bool: attrSet: if bool then attrSet else { };
  writeNuApplication = import ../lib/writeNuApplication { inherit lib pkgs; };
  notify = pkgs.callPackage ./notify { inherit generate-kaomoji writeNuApplication; };
in
rec {
  default = pkgs.callPackage ./cache-command { };
  apple-emoji-linux = pkgs.callPackage ./apple-emoji-linux { };
  better-branch = pkgs.callPackage ./better-branch { inherit writeNuApplication; };
  cache-command = pkgs.callPackage ./cache-command { };
  ff = pkgs.callPackage ./ff { };
  # g = pkgs.callPackage ./g { };
  is-sshed = pkgs.callPackage ./is-sshed { };
  j = pkgs.callPackage ./j { };
  jira-list = pkgs.callPackage ./jira-list { inherit cache-command; };
  jira-task-list = pkgs.callPackage ./jira-task-list { inherit cache-command; };
  localip = pkgs.callPackage ./localip { inherit writeNuApplication; };
  inherit notify;
  nvim = pkgs.callPackage ./nvim { };
  prs = pkgs.callPackage ./prs { inherit writeNuApplication; };
  review = pkgs.callPackage ./review { inherit writeNuApplication; };
  searcher = pkgs.callPackage ./searcher { inherit writeNuApplication; };
  tmux-tab-name-update = pkgs.callPackage ./tmux-tab-name-update { };
  uair-toggle-and-notify = pkgs.callPackage ./uair-toggle-and-notify { inherit notify; };
  update-package-lock = pkgs.callPackage ./update-package-lock { inherit writeNuApplication; };
  zellij-tab-name-update = pkgs.callPackage ./zellij-tab-name-update { };
}
// (optionalAttrs pkgs.stdenv.isDarwin {
  fix-yabai = pkgs.callPackage ./fix-yabai { inherit writeNuApplication; };
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
