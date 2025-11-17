# Based on:
# https://github.com/Misterio77/nix-config/blob/e360a9ecf6de7158bea813fc075f3f6228fc8fc0/pkgs/default.nix
{
  pkgs ? import <nixpkgs>,
  generate-kaomoji,
  nuenv,
}:
let
  optionalAttrs = bool: attrSet: if bool then attrSet else { };
  writeNuApplication = nuenv.mkNushellScriptApplication pkgs.nushell pkgs.writeTextFile pkgs.lib;
  notify = pkgs.callPackage ./notify { inherit generate-kaomoji writeNuApplication; };
  base-ref = pkgs.callPackage ./base-ref { inherit writeNuApplication; };
  zenity-askpass = pkgs.callPackage ./zenity-askpass { inherit writeNuApplication; };
in
rec {
  inherit base-ref notify;
  default = pkgs.callPackage ./cache-command { };
  apple-emoji-linux = pkgs.callPackage ./apple-emoji-linux { };
  better-branch = pkgs.callPackage ./better-branch { inherit writeNuApplication; };
  cache-command = pkgs.callPackage ./cache-command { };
  claude-code = pkgs.callPackage ./claude-code { };
  claude-code-npm = pkgs.callPackage ./claude-code/npm.nix { };
  claude-code-update = pkgs.callPackage ./claude-code/update.nix { inherit writeNuApplication; };
  ff = pkgs.callPackage ./ff { };
  git-amend = pkgs.callPackage ./git-amend { inherit writeNuApplication; };
  gp = pkgs.callPackage ./gp { inherit update-pr writeNuApplication; };
  is-sshed = pkgs.callPackage ./is-sshed { inherit writeNuApplication; };
  j = pkgs.callPackage ./j { };
  jira-list = pkgs.callPackage ./jira-list { inherit cache-command; };
  jira-task-list = pkgs.callPackage ./jira-task-list { inherit cache-command; };
  localip = pkgs.callPackage ./localip { inherit writeNuApplication; };
  log-pr = pkgs.callPackage ./log-pr { inherit writeNuApplication; };
  nix-repl = pkgs.callPackage ./nix-repl { inherit writeNuApplication; };
  nvim = pkgs.callPackage ./nvim { };
  pgpod = pkgs.callPackage ./pgpod { inherit writeNuApplication; };
  prs = pkgs.callPackage ./prs { inherit writeNuApplication; };
  pr-summary = pkgs.callPackage ./pr-summary { inherit base-ref writeNuApplication; };
  review = pkgs.callPackage ./review { inherit writeNuApplication; };
  searcher = pkgs.callPackage ./searcher { inherit writeNuApplication; };
  tmux-tab-name-update = pkgs.callPackage ./tmux-tab-name-update { inherit writeNuApplication; };
  toggle-theme = pkgs.callPackage ./toggle-theme { inherit writeNuApplication; };
  uair-toggle-and-notify = pkgs.callPackage ./uair-toggle-and-notify { inherit notify; };
  update-package-lock = pkgs.callPackage ./update-package-lock { inherit writeNuApplication; };
  update-pr = pkgs.callPackage ./update-pr { inherit pr-summary writeNuApplication; };
  whisper-transcribe = pkgs.callPackage ./whisper-transcribe { inherit writeNuApplication; };
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
  inherit zenity-askpass;
  move-active = pkgs.callPackage ./move-active { inherit writeNuApplication; };
  openrgb-appimage = pkgs.callPackage ./openrgb-appimage { };
  record = pkgs.callPackage ./record { };
  record-section = pkgs.callPackage ./record-section { };
  rofi-cliphist = pkgs.callPackage ./rofi-cliphist { inherit writeNuApplication; };
  rofi-powermenu = pkgs.callPackage ./rofi-powermenu { inherit writeNuApplication; };
})
