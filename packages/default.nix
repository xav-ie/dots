# Based on:
# https://github.com/Misterio77/nix-config/blob/e360a9ecf6de7158bea813fc075f3f6228fc8fc0/pkgs/default.nix
{
  pkgs ? import <nixpkgs>,
  pkgs-unfree ? pkgs, # For packages needing allowUnfree (claude-code)
  pkgs-bleeding ? pkgs, # For packages needing newer Python deps (mcp-atlassian)
  # Platform flags passed from caller to avoid pkgs.stdenv access here
  isDarwin ? pkgs.stdenv.isDarwin,
  isLinux ? pkgs.stdenv.isLinux,
  executor-src,
  generate-kaomoji,
  mcp-atlassian-src,
  nuenv,
  simulstreaming-src,
  slack-mcp-server-src,
  zerobrew-src,
}:
let
  optionalAttrs = bool: attrSet: if bool then attrSet else { };
  writeNuApplication = nuenv.mkNushellScriptApplication pkgs.nushell pkgs.writeTextFile pkgs.lib;
  notify = pkgs.callPackage ./notify { inherit generate-kaomoji writeNuApplication; };
in
rec {
  inherit notify;
  default = pkgs.callPackage ./cache-command { };
  apple-emoji-linux = pkgs.callPackage ./apple-emoji-linux { };
  base-ref = pkgs.callPackage ./base-ref { inherit writeNuApplication; };
  better-branch = pkgs.callPackage ./better-branch { inherit writeNuApplication; };
  cache-command = pkgs.callPackage ./cache-command { };
  discord-mcp = pkgs.callPackage ./discord-mcp { };
  executor = pkgs.callPackage ./executor { inherit executor-src; };
  # claude-code packages need allowUnfree, passed via pkgs-unfree
  chrome-headless-shell = pkgs.callPackage ./chrome-headless-shell { };
  claude-code = pkgs-unfree.callPackage ./claude-code { };
  claude-code-npm = pkgs-unfree.callPackage ./claude-code/npm.nix { };
  claude-code-update = pkgs-unfree.callPackage ./claude-code/update.nix {
    inherit writeNuApplication;
  };
  ff = pkgs.callPackage ./ff { };
  flint = pkgs.callPackage ./flint { inherit format-staged lint-staged writeNuApplication; };
  format-staged = pkgs.callPackage ./format-staged { inherit writeNuApplication; };
  git-amend = pkgs.callPackage ./git-amend { inherit writeNuApplication; };
  gp = pkgs.callPackage ./gp { inherit update-pr writeNuApplication; };
  is-sshed = pkgs.callPackage ./is-sshed { inherit writeNuApplication; };
  lint-staged = pkgs.callPackage ./lint-staged { inherit writeNuApplication; };
  localip = pkgs.callPackage ./localip { inherit writeNuApplication; };
  mcp-atlassian = pkgs.callPackage ./mcp-atlassian { inherit mcp-atlassian-src pkgs-bleeding; };
  mcp-sse-client = pkgs.callPackage ./mcp-sse-client { };
  log-pr = pkgs.callPackage ./log-pr { inherit writeNuApplication; };
  nix-flamegraph = pkgs.callPackage ./nix-flamegraph { inherit writeNuApplication; };
  nix-output-monitor = pkgs.callPackage ./nix-output-monitor { };
  nix-repl = pkgs.callPackage ./nix-repl { inherit writeNuApplication; };
  nom-run = pkgs.callPackage ./nom-run { inherit nix-output-monitor writeNuApplication; };
  nvim = pkgs.callPackage ./nvim { };
  pgpod = pkgs.callPackage ./pgpod { inherit writeNuApplication; };
  pr-summary = pkgs.callPackage ./pr-summary { inherit base-ref writeNuApplication; };
  prettier-plugin-toml = pkgs.callPackage ./prettier-plugin-toml { };
  prettier-with-toml = pkgs.callPackage ./prettier-with-toml { inherit prettier-plugin-toml; };
  prs = pkgs.callPackage ./prs { inherit writeNuApplication; };
  review = pkgs.callPackage ./review { inherit writeNuApplication; };
  searcher = pkgs.callPackage ./searcher { inherit writeNuApplication; };
  slack-mcp-server = pkgs.callPackage ./slack-mcp-server { src = slack-mcp-server-src; };
  tmux-move-window = pkgs.callPackage ./tmux-move-window { inherit writeNuApplication; };
  tmux-tab-name-update = pkgs.callPackage ./tmux-tab-name-update { };
  toggle-theme = pkgs.callPackage ./toggle-theme { inherit writeNuApplication; };
  uair-toggle-and-notify = pkgs.callPackage ./uair-toggle-and-notify { inherit notify; };
  update-package-lock = pkgs.callPackage ./update-package-lock { inherit writeNuApplication; };
  update-pr = pkgs.callPackage ./update-pr { inherit pr-summary writeNuApplication; };
  whisper-transcribe = pkgs.callPackage ./whisper-transcribe {
    inherit pkgs-unfree writeNuApplication;
  };
  pi-executor = pkgs.callPackage ./pi-executor { };
  pi-readcache = pkgs.callPackage ./pi-readcache { };
  pi-show-diffs = pkgs.callPackage ./pi-show-diffs { };
  zellij-tab-name-update = pkgs.callPackage ./zellij-tab-name-update { };

}
// (optionalAttrs isDarwin {
  fix-yabai = pkgs.callPackage ./fix-yabai { inherit writeNuApplication; };
  focus-or-open-application = pkgs.callPackage ./focus-or-open-application {
    inherit writeNuApplication;
  };
  move-pip = pkgs.callPackage ./move-pip { inherit writeNuApplication; };
  sketchybar-battery = pkgs.callPackage ./sketchybar-battery { inherit writeNuApplication; };
  zerobrew = pkgs.callPackage ./zerobrew { src = zerobrew-src; };
  tcc-grant = pkgs.callPackage ./tcc-grant { inherit writeNuApplication; };
})
// (optionalAttrs isLinux {
  claude-overlay = pkgs.callPackage ./claude-overlay { };
  claude-yolo = pkgs.callPackage ./claude-yolo { };
  move-active = pkgs.callPackage ./move-active { inherit writeNuApplication; };
  openrgb-appimage = pkgs.callPackage ./openrgb-appimage { };
  simulstreaming = pkgs.callPackage ./simulstreaming { src = simulstreaming-src; };
  record = pkgs.callPackage ./record { };
  record-section = pkgs.callPackage ./record-section { };
  rofi-cliphist = pkgs.callPackage ./rofi-cliphist { inherit writeNuApplication; };
  rofi-powermenu = pkgs.callPackage ./rofi-powermenu { inherit writeNuApplication; };
  zenity-askpass = pkgs.callPackage ./zenity-askpass { inherit writeNuApplication; };
})
