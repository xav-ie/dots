# Based on:
# https://github.com/Misterio77/nix-config/blob/e360a9ecf6de7158bea813fc075f3f6228fc8fc0/pkgs/default.nix
{
  pkgs ? import <nixpkgs>,
  pkgs-unfree ? pkgs, # For packages needing allowUnfree (claude-code)
  pkgs-bleeding ? pkgs, # For packages needing newer Python deps (mcp-atlassian)
  # Platform flags passed from caller to avoid pkgs.stdenv access here
  isDarwin ? pkgs.stdenv.isDarwin,
  isLinux ? pkgs.stdenv.isLinux,
  # ags package set (inputs.ags.packages.<system>); null on darwin, unused there.
  agsPackages ? null,
  # virtual-headset mute control CLI (inputs.virtual-headset); linux-only, used
  # by the ags bar. null on darwin.
  virtual-headset-ctl ? null,
  # virtual-headset AGS panel (inputs.virtual-headset); opened from the bar's
  # right-click. linux-only, null on darwin.
  virtual-headset-panel ? null,
  # The morrow calendar app (inputs.morrow.packages.<system>.default); built
  # with default fonts, re-overridden below to track lib/fonts.nix. null on
  # darwin, where morrow has no output and morrow.nix is not imported.
  morrow-pkg ? null,
  # The ream PDF-tools app (inputs.ream.packages.<system>.default); null on
  # darwin, where ream has no output and the consuming module isn't imported.
  ream-pkg ? null,
  # browser-session-mcp, extracted to its own repo
  # (inputs.browser-session-mcp.packages.<system>.default); linux-only.
  browser-session-mcp-pkg ? null,
  # Overlay-patched atuin (pty-proxy OSC-7 cwd tracking, #3461) built at the
  # flake level; must be the same patched build the profile uses so tmux-shell's
  # proxy chdir's and pane_current_path tracks the shell's cwd.
  atuin,
  # uair patched with PR#31 (overlays/default.nix), threaded in from packages.nix
  # for the same reason: `uairctl listen` must be newline-delimited and flushed so
  # the AGS bar can stream it. Forwarded to the bar below.
  uair,
  bun-demincer-src,
  clauhist-src,
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
  # claude-code packages need allowUnfree, passed via pkgs-unfree
  claude-code = pkgs-unfree.callPackage ./claude-code { };
  claude-code-extract = pkgs-unfree.callPackage ./claude-code/extract.nix {
    inherit bun-demincer-src nodejs_25;
  };
  claude-code-npm = pkgs-unfree.callPackage ./claude-code/npm.nix {
    inherit bun-demincer-src nodejs_25;
  };
  claude-code-update = pkgs-unfree.callPackage ./claude-code/update.nix {
    inherit writeNuApplication;
  };
  clauhist = pkgs.callPackage ./clauhist { inherit clauhist-src; };
  ff = pkgs.callPackage ./ff { };
  firefox-router = pkgs.callPackage ./firefox-router { };
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
  nodejs_25 = pkgs.callPackage ./nodejs_25 { };
  process-logger = pkgs.callPackage ./process-logger { inherit nodejs_25; };
  nix-output-monitor = pkgs.callPackage ./nix-output-monitor { };
  nix-repl = pkgs.callPackage ./nix-repl { inherit writeNuApplication; };
  nom-run = pkgs.callPackage ./nom-run { inherit nix-output-monitor writeNuApplication; };
  nvim = pkgs.callPackage ./nvim { };
  osgrep-indexed = pkgs.callPackage ./osgrep-indexed { };
  pgpod = pkgs.callPackage ./pgpod { inherit writeNuApplication; };
  pr-summary = pkgs.callPackage ./pr-summary { inherit base-ref writeNuApplication; };
  prettier-plugin-toml = pkgs.callPackage ./prettier-plugin-toml { };
  prettier-with-toml = pkgs.callPackage ./prettier-with-toml { inherit prettier-plugin-toml; };
  nu_plugin_prompt = pkgs.callPackage ./nu_plugin_prompt { inherit pkgs-bleeding; };
  prs = pkgs.callPackage ./prs { inherit writeNuApplication; };
  review = pkgs.callPackage ./review { inherit writeNuApplication; };
  searcher = pkgs.callPackage ./searcher { inherit writeNuApplication; };
  slack-mcp-server = pkgs.callPackage ./slack-mcp-server { src = slack-mcp-server-src; };
  ssh-praesidium-route = pkgs.callPackage ./ssh-praesidium-route { inherit writeNuApplication; };
  tm = pkgs.callPackage ./tm { };
  tmux-claude-resurrect = pkgs.callPackage ./tmux-claude-resurrect { };
  tmux-move-window = pkgs.callPackage ./tmux-move-window { inherit writeNuApplication; };
  tmux-is-vim-in-tree = pkgs.callPackage ./tmux-is-vim-in-tree { };
  tmux-shell = pkgs.callPackage ./tmux-shell { inherit atuin pkgs-bleeding; };
  tmux-tab-name-update = pkgs.callPackage ./tmux-tab-name-update { };
  toggle-theme = pkgs.callPackage ./toggle-theme { inherit writeNuApplication; };
  tsc-filter = pkgs.callPackage ./tsc-filter { inherit writeNuApplication; };
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
  focus-daemon = pkgs.callPackage ./focus-daemon { };
  move-pip = pkgs.callPackage ./move-pip { };
  sketchybar-battery = pkgs.callPackage ./sketchybar-battery { inherit writeNuApplication; };
  sketchybar-hover = pkgs.callPackage ./sketchybar-hover { };
  zerobrew = pkgs.callPackage ./zerobrew { src = zerobrew-src; };
  tcc-grant = pkgs.callPackage ./tcc-grant { inherit writeNuApplication; };
})
// (optionalAttrs isLinux rec {
  askpass = pkgs.callPackage ./askpass {
    inherit agsPackages;
    fontName = (import ../modules/_lib/fonts.nix { inherit pkgs; }).fonts.name "sans";
  };
  bar = pkgs.callPackage ./bar {
    inherit
      agsPackages
      notification-center
      pickers
      uair
      virtual-headset-ctl
      virtual-headset-panel
      ;
    # Plain (non-CUDA) build: the bar only needs the `record toggle` IPC client,
    # which never loads whisper, so it stays out of the heavy GPU closure.
    inherit (pkgs-bleeding) hyprwhspr-rs;
    # uair-toggle-and-notify lives in the base (non-Linux) set, out of scope
    # here; rebuild it from the same inputs (identical store path).
    uair-toggle-and-notify = pkgs.callPackage ./uair-toggle-and-notify { inherit notify; };
    fontName = (import ../modules/_lib/fonts.nix { inherit pkgs; }).fonts.name "sans";
  };
  browser-session-mcp = browser-session-mcp-pkg;
  chrome-headless-shell = pkgs.callPackage ./chrome-headless-shell { };
  claude-overlay = pkgs.callPackage ./claude-overlay { };
  claude-yolo = pkgs.callPackage ./claude-yolo { };
  executor = pkgs.callPackage ./executor { inherit executor-src; };
  move-active = pkgs.callPackage ./move-active { inherit writeNuApplication; };
  # Built upstream in the morrow flake; override only the fonts so it tracks the
  # same lib/fonts.nix `sans`/`mono` families as the rest of the GTK config.
  morrow = morrow-pkg.override {
    fontName = (import ../modules/_lib/fonts.nix { inherit pkgs; }).fonts.name "sans";
    monoFont = (import ../modules/_lib/fonts.nix { inherit pkgs; }).fonts.name "mono";
  };
  notification-center = pkgs.callPackage ./notification-center {
    inherit agsPackages;
    fontName = (import ../modules/_lib/fonts.nix { inherit pkgs; }).fonts.name "sans";
  };
  openrgb-appimage = pkgs.callPackage ./openrgb-appimage { };
  pickers = pkgs.callPackage ./pickers {
    inherit agsPackages;
    fontName = (import ../modules/_lib/fonts.nix { inherit pkgs; }).fonts.name "sans";
  };
  pinentry-auto = pkgs.callPackage ./pinentry-auto { };
  power-arbiter = pkgs.callPackage ./power-arbiter { };
  # Built upstream in the ream flake (extracted repo); consumed as-is.
  ream = ream-pkg;
  simulstreaming = pkgs.callPackage ./simulstreaming { src = simulstreaming-src; };
  record = pkgs.callPackage ./record { };
  record-section = pkgs.callPackage ./record-section { };
  screencast-border = pkgs.callPackage ./screencast-border {
    inherit agsPackages;
    fontName = (import ../modules/_lib/fonts.nix { inherit pkgs; }).fonts.name "sans";
  };
  snippet-mcp = pkgs.callPackage ./snippet-mcp { };
})
