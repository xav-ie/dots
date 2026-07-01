{
  description = "Xavier's NixOS";
  inputs = {
    ags.url = "github:aylur/ags";
    ags.inputs.astal.follows = "astal";
    ags.inputs.nixpkgs.follows = "nixpkgs";
    alacritty-theme.url = "github:alexghr/alacritty-theme.nix";
    astal.url = "github:aylur/astal";
    astal.inputs.nixpkgs.follows = "nixpkgs";
    atuin.url = "github:atuinsh/atuin";
    beads.url = "github:steveyegge/beads";
    # LOCAL: extracted from packages/browser-session-mcp; testing via local path
    # before pushing to github:xav-ie/browser-session-mcp.
    browser-session-mcp.url = "git+ssh://git@github.com/xav-ie/browser-session-mcp";
    browser-session-mcp.inputs.nixpkgs.follows = "nixpkgs";
    ctpv.url = "github:xav-ie/ctpv-nix";
    flake-parts.url = "github:hercules-ci/flake-parts";
    generate-kaomoji.url = "github:xav-ie/generate-kaomoji";
    hardware.url = "github:nixos/nixos-hardware";
    home-manager.url = "github:nix-community/home-manager";
    hyprland.url = "git+https://github.com/hyprwm/Hyprland?submodules=1";
    import-tree.url = "github:vic/import-tree";
    mcp-nixos.url = "github:utensils/mcp-nixos";
    morlana.url = "github:ryanccn/morlana";
    morrow.url = "git+ssh://git@github.com/xav-ie/morrow";
    morrow.inputs.nixpkgs.follows = "nixpkgs";
    morrow.inputs.ags.follows = "ags";
    # Static board-poster generator; builds a single self-contained board.html
    # served at muscat.lalala.casa. Source-only (no flake.nix); built in packages/muscat.
    muscat-src.url = "git+ssh://git@github.com/xav-ie/Muscat";
    muscat-src.flake = false;
    himalaya-latest.url = "github:xav-ie/himalaya?ref=xav/fix-deprecation-warnings";
    pimalaya-core.url = "github:pimalaya/core";
    pimalaya-core.flake = false;
    neverest.url = "github:pimalaya/neverest";
    nix-auto-follow.url = "github:xav-ie/nix-auto-follow/feat-consolidation";
    nix-darwin.url = "github:LnL7/nix-darwin";
    nix-homebrew.url = "github:zhaofengli-wip/nix-homebrew";
    nixpkgs-bleeding.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-homeassistant.url = "github:nixos/nixpkgs/master";
    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-26.05";
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nuenv.url = "github:xav-ie/nuenv";
    plover-flake.url = "github:openstenoproject/plover-flake";
    quadlet-nix.url = "github:SEIAROTg/quadlet-nix";
    ream.url = "git+ssh://git@github.com/xav-ie/ream";
    ream.inputs.nixpkgs.follows = "nixpkgs";
    sops-nix.url = "github:Mic92/sops-nix";
    virtual-headset.url = "github:xav-ie/virtual-headset";
    systems.url = "github:xav-ie/dots-systems";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    zjstatus.url = "github:dj95/zjstatus";
    # Swift is broken on Linux with GCC 14 (nixpkgs#462451), pin to last working version
    nixpkgs-swift.url = "github:nixos/nixpkgs/3c3988cce18bf31db263dd0374e34cb65e696def";
    # TODO: figure out how to use from misterio and vimjoyer
    # impermanence.url = "github:nix-community/impermanence";
    # nix-colors.url = "github:misterio77/nix-colors";

    # transitive deps that are used by multiple inputs
    crane.url = "github:ipetkov/crane";
    fenix.url = "github:nix-community/fenix";
    fenix-neverest.url = "github:soywod/fenix";
    flake-compat.url = "github:edolstra/flake-compat";
    flake-utils.url = "github:numtide/flake-utils";
    gitignore.url = "github:hercules-ci/gitignore.nix";
    nixpkgs-lib.url = "github:nix-community/nixpkgs.lib";
    pimalaya-neverest.url = "github:xav-ie/nix?ref=xav/fix-warnings-neverest-compat";
    pimalaya-neverest.flake = false;
    # Fork carrying the `fix(mastra): use dedicated postgres schema`
    # change. Revert to `github:gitroomhq/postiz-app/v2.21.6` (or
    # whatever release ships the fix) once it lands upstream.
    postiz-src.flake = false;
    postiz-src.url = "github:xav-ie/postiz-app/fix/skip-db-push-on-restart";
    rust-analyzer-src.url = "github:rust-lang/rust-analyzer/nightly";
    rust-analyzer-src.flake = false;
    rust-overlay.url = "github:oxalica/rust-overlay";

    # overrides
    alacritty-theme-themes.flake = false;
    alacritty-theme-themes.url = "github:alacritty/alacritty-theme";
    alacritty-theme.inputs.alacritty-theme.follows = "alacritty-theme-themes";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs-lib-v1-merge";
    # before v2 merge check
    nixpkgs-lib-v1-merge.url = "github:nix-community/nixpkgs.lib/a73b9c743612e4244d865a2fdee11865283c04e6";

    # vendored
    # Claude Code marketplaces (pinned for reproducibility)
    claude-marketplace-official.flake = false;
    claude-marketplace-official.url = "github:anthropics/claude-plugins-official";
    claude-marketplace-outsmartly.flake = false;
    claude-marketplace-outsmartly.url = "git+ssh://git@github.com/outsmartly/claude-plugins";
    claude-marketplace-lsps.flake = false;
    claude-marketplace-lsps.url = "github:Piebald-AI/claude-code-lsps";
    claude-marketplace-mgrep.flake = false;
    claude-marketplace-mgrep.url = "github:mixedbread-ai/mgrep";
    claude-marketplace-osgrep.flake = false;
    claude-marketplace-osgrep.url = "github:Ryandonofrio3/osgrep";

    glsl_analyzer.flake = false;
    glsl_analyzer.url = "github:xav-ie/glsl_analyzer/format";
    homebrew-bundle.flake = false;
    homebrew-bundle.url = "github:homebrew/homebrew-bundle";
    homebrew-cask.flake = false;
    homebrew-cask.url = "github:homebrew/homebrew-cask";
    homebrew-core.flake = false;
    homebrew-core.url = "github:homebrew/homebrew-core";
    obs-backgroundremoval.flake = false;
    obs-backgroundremoval.url = "github:royshil/obs-backgroundremoval";
    ollama-src.flake = false;
    ollama-src.url = "github:ollama/ollama/v0.13.5";
    ralph-src.url = "github:snarktank/ralph";
    ralph-src.flake = false;
    simulstreaming-src.url = "github:ufal/SimulStreaming";
    simulstreaming-src.flake = false;
    mcp-atlassian-src.url = "github:sooperset/mcp-atlassian/v0.21.0";
    mcp-atlassian-src.flake = false;
    slack-mcp-server.url = "github:korotovsky/slack-mcp-server/v1.2.3";
    slack-mcp-server.flake = false;
    executor-src.url = "github:RhysSullivan/executor/v1.4.19";
    executor-src.flake = false;
    bun-demincer-src.url = "github:xav-ie/bun-demincer/fix/linux-dataStart-byte-count";
    bun-demincer-src.flake = false;
    clauhist-src.url = "github:lef237/clauhist";
    clauhist-src.flake = false;
    macos-corner-fix-src.url = "github:m4rkw/macos-corner-fix/147f2708cb468475567139acbad7d714859a4b67";
    macos-corner-fix-src.flake = false;
    zerobrew-src.url = "github:lucasgelfond/zerobrew";
    zerobrew-src.flake = false;

    # no way around this :/
    alacritty-theme.inputs.flake-parts.follows = "flake-parts";
    alacritty-theme.inputs.nixpkgs.follows = "nixpkgs";
    beads.inputs.flake-utils.follows = "flake-utils";
    beads.inputs.nixpkgs.follows = "nixpkgs";
    ctpv.inputs.flake-utils.follows = "flake-utils";
    ctpv.inputs.nixpkgs.follows = "nixpkgs";
    flake-utils.inputs.systems.follows = "systems";
    generate-kaomoji.inputs.flake-utils.follows = "flake-utils";
    generate-kaomoji.inputs.nixpkgs.follows = "nixpkgs";
    gitignore.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    himalaya-latest.inputs.nixpkgs.follows = "nixpkgs";
    hyprland.inputs.nixpkgs.follows = "nixpkgs";
    hyprland.inputs.systems.follows = "systems";
    mcp-nixos.inputs.flake-parts.follows = "flake-parts";
    mcp-nixos.inputs.nixpkgs.follows = "nixpkgs";
    fenix-neverest.inputs.nixpkgs.follows = "nixpkgs";
    fenix-neverest.inputs.rust-analyzer-src.follows = "rust-analyzer-src";
    morlana.inputs.nixpkgs.follows = "nixpkgs";
    neverest.inputs.fenix.follows = "fenix-neverest";
    neverest.inputs.pimalaya.follows = "pimalaya-neverest";
    nix-auto-follow.inputs.nixpkgs.follows = "nixpkgs";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    nuenv.inputs.nixpkgs.follows = "nixpkgs";
    nuenv.inputs.systems.follows = "systems";
    plover-flake.inputs.nixpkgs.follows = "nixpkgs";
    rust-overlay.inputs.nixpkgs.follows = "nixpkgs";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
    virtual-headset.inputs.crane.follows = "crane";
    virtual-headset.inputs.flake-parts.follows = "flake-parts";
    virtual-headset.inputs.home-manager.follows = "home-manager";
    virtual-headset.inputs.nixpkgs.follows = "nixpkgs";
    virtual-headset.inputs.nuenv.follows = "nuenv";
    virtual-headset.inputs.systems.follows = "systems";
    virtual-headset.inputs.treefmt-nix.follows = "treefmt-nix";
    zjstatus.inputs.crane.follows = "crane";
    zjstatus.inputs.flake-utils.follows = "flake-utils";
    zjstatus.inputs.nixpkgs.follows = "nixpkgs";
    zjstatus.inputs.rust-overlay.follows = "rust-overlay";
  };

  # Dendritic: every *.nix under ./modules is a flake-parts module, auto-imported
  # by import-tree. Flake-level machinery lives in ./modules/flake, nixos/darwin/
  # home config in concern files, and the hosts in ./modules/hosts assemble them.
  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        (inputs.import-tree ./modules)
      ];
    };
}
