{
  description = "Xavier's NixOS";
  inputs = {
    alacritty-theme.url = "github:alexghr/alacritty-theme.nix";
    atuin.url = "github:xav-ie/atuin/feat/osc7-helper";
    beads.url = "github:steveyegge/beads";
    ctpv.url = "github:xav-ie/ctpv-nix";
    flake-parts.url = "github:hercules-ci/flake-parts";
    generate-kaomoji.url = "github:xav-ie/generate-kaomoji";
    hardware.url = "github:nixos/nixos-hardware";
    home-manager.url = "github:nix-community/home-manager";
    hyprland.url = "git+https://github.com/hyprwm/Hyprland?submodules=1";
    mcp-nixos.url = "github:utensils/mcp-nixos";
    morlana.url = "github:ryanccn/morlana";
    himalaya-latest.url = "github:pimalaya/himalaya";
    pimalaya-core.url = "github:pimalaya/core";
    pimalaya-core.flake = false;
    neverest.url = "github:pimalaya/neverest";
    nix-auto-follow.url = "github:xav-ie/nix-auto-follow/feat-consolidation";
    nix-darwin.url = "github:LnL7/nix-darwin";
    nix-homebrew.url = "github:zhaofengli-wip/nix-homebrew";
    nixpkgs-bleeding.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-homeassistant.url = "github:nixos/nixpkgs/master";
    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-25.05";
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nuenv.url = "github:xav-ie/nuenv";
    plover-flake.url = "github:openstenoproject/plover-flake";
    quadlet-nix.url = "github:SEIAROTg/quadlet-nix";
    sops-nix.url = "github:Mic92/sops-nix";
    virtual-headset.url = "github:xav-ie/virtual-headset";
    systems.url = "github:xav-ie/dots-systems";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    waybar.url = "github:Alexays/waybar";
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
    pimalaya-neverest.url = "github:pimalaya/nix/be23e0deeb014c6be5232322b892c9bee25dee77";
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
    waybar.inputs.flake-compat.follows = "flake-compat";
    waybar.inputs.nixpkgs.follows = "nixpkgs";
    zjstatus.inputs.crane.follows = "crane";
    zjstatus.inputs.flake-utils.follows = "flake-utils";
    zjstatus.inputs.nixpkgs.follows = "nixpkgs";
    zjstatus.inputs.rust-overlay.follows = "rust-overlay";
  };

  outputs =
    inputs@{ flake-parts, ... }:
    let
      systems' = import inputs.systems;
      # Memoize unfree pkgs per-system at flake level (evaluated once, shared)
      pkgsUnfreeFor = inputs.nixpkgs.lib.genAttrs systems' (
        system:
        import inputs.nixpkgs {
          inherit system;
          config.allowUnfree = true;
        }
      );
    in
    flake-parts.lib.mkFlake { inherit inputs; } (toplevel: {
      debug = true;

      systems = systems';

      imports = [
        # inputs.git-hooks.flakeModule
        inputs.treefmt-nix.flakeModule
        (import ./home-manager/modules/git/flake-check.nix toplevel)
        (import ./packages/clippy-checks.nix inputs)
        ./lib/nix-multiline-lint
      ];

      perSystem =
        {
          config,
          lib,
          pkgs,
          system,
          ...
        }:
        {
          # uncomment if you need overlays at the top level for some reason...
          # _module.args.pkgs = import inputs.nixpkgs {
          #   inherit system;
          #   overlays = builtins.attrValues self.overlays;
          # };

          devShells.default = pkgs.mkShell {
            packages =
              (with pkgs; [
                just
                nix-diff
                nushell
              ])
              ++ (with config.packages; [
                nom-run
                nix-output-monitor
              ])
              ++ lib.optionals pkgs.stdenv.isLinux (
                with pkgs;
                [
                  nh
                  nixos-rebuild
                ]
              )
              ++ lib.optionals pkgs.stdenv.isDarwin [
                inputs.morlana.packages.${system}.default
                inputs.nix-darwin.packages.${system}.default
              ]
              ++ [ config.formatter ]
              ++ [ inputs.nix-auto-follow.packages.${system}.default ];

            shellHook = ''
              printf "\n🐢 Use \e[32;40mjust\e[0m to build the system."
              printf "\n💄 Use \e[32;40mtreefmt\e[0m to format the files."
            '';
          };

          packages = import ./packages {
            atuin = inputs.atuin.packages.${system}.default;
            generate-kaomoji = inputs.generate-kaomoji.packages.${system}.default;
            # Use regular nixpkgs - most packages are writeNuApplication wrappers
            # that don't need bleeding-edge.
            inherit pkgs;
            # Compute platform from system string - avoids forcing pkgs.stdenv evaluation
            isDarwin = lib.hasSuffix "-darwin" system;
            isLinux = lib.hasSuffix "-linux" system;
            # Memoized unfree pkgs (shared across evaluations)
            pkgs-unfree = pkgsUnfreeFor.${system};
            pkgs-bleeding = import inputs.nixpkgs-bleeding {
              inherit system;
              config.allowUnfree = true;
              overlays = [
                (_: bleedPrev: {
                  pythonPackagesExtensions = bleedPrev.pythonPackagesExtensions ++ [
                    (_: pyPrev: {
                      # fastmcp's pytest suite hangs in the sandbox on async tests.
                      # pytest-check-hook registers pytestCheckPhase unconditionally,
                      # so dontUsePytestCheck is the only way to skip it.
                      fastmcp = pyPrev.fastmcp.overridePythonAttrs (_: {
                        dontUsePytestCheck = true;
                      });
                    })
                  ];
                })
              ];
            };
            nuenv = inputs.nuenv.lib;
            inherit (inputs)
              bun-demincer-src
              clauhist-src
              executor-src
              mcp-atlassian-src
              simulstreaming-src
              zerobrew-src
              ;
            slack-mcp-server-src = inputs.slack-mcp-server;
          };

          treefmt =
            { options, ... }:
            let
              # Swift is broken on Linux with GCC 14, use pinned nixpkgs
              pkgs-swift = import inputs.nixpkgs-swift { inherit system; };

              glsl_analyzer = pkgs.glsl_analyzer.overrideAttrs (_oldAttrs: {
                src = inputs.glsl_analyzer;
                nativeBuildInputs = [ pkgs.zig.hook ];
                postPatch = ''
                  substituteInPlace build.zig \
                    --replace-fail 'b.run(&.{ "git", "describe", "--tags", "--always" })' '"dev"'
                '';
              });

              # Custom GLSL formatter module
              glslFormatterModule =
                { mkFormatterModule, ... }:
                {
                  imports = [
                    (mkFormatterModule {
                      name = "glsl_analyzer";
                      package = "glsl_analyzer";
                      args = [
                        "--tab-size=2"
                        "--format"
                      ];
                      includes = [ "*.glsl" ];
                    })
                  ];
                };

              # Custom go.mod formatter module
              goModFormatterModule =
                { mkFormatterModule, ... }:
                {
                  imports = [
                    (mkFormatterModule {
                      name = "go-mod-fmt";
                      package = "go";
                      args = [
                        "mod"
                        "edit"
                        "-fmt"
                      ];
                      includes = [ "**/go.mod" ];
                    })
                  ];
                };
            in
            {
              imports = [
                glslFormatterModule
                goModFormatterModule
              ];

              programs = {
                # buggy so far...
                # nufmt.enable = true;
                clang-format = {
                  enable = true;
                  # Default `includes` is C/C++/headers only; opt Objective-C in.
                  includes = options.programs.clang-format.includes.default ++ [
                    "*.m"
                    "*.mm"
                  ];
                  # Exclude GLSL files - they have special comment syntax that clang-format mangles
                  excludes = [ "*.glsl" ];
                };
                deadnix.enable = true;
                glsl_analyzer = {
                  enable = true;
                  package = glsl_analyzer;
                };
                just.enable = true;
                kdlfmt.enable = true;
                go-mod-fmt.enable = true;
                gofmt.enable = true;
                nixfmt.enable = true;
                prettier = {
                  enable = true;
                  package = config.packages.prettier-with-toml;
                  includes = options.programs.prettier.includes.default ++ [
                    "*.cfg"
                    "*.toml"
                  ];
                };
                ruff.enable = true;
                rustfmt.enable = true;
                shfmt.enable = true;
                statix.enable = true;
                swift-format = {
                  enable = true;
                  package = pkgs-swift.swift-format;
                };
              };
              settings = {
                on-unmatched = "fatal";
                excludes = [
                  "**/.gitignore"
                  "**/.inputrc"
                  "**/*.modulemap"
                  "**/.npmrc"
                  "**/Cargo.lock"
                  "*.awk"
                  "*.conf"
                  "*.nu" # formatter is borked
                  "*.patch"
                  "*.scpt" # no standard formatter for AppleScript
                  ".git-blame-ignore-revs"
                  ".gitignore"
                  "flake.lock"
                  "secrets/*.yaml" # sops has its own formatter
                ];
              };
            };

        };

      flake = {
        overlays = import ./overlays toplevel;
        darwinConfigurations = import ./darwinConfigurations toplevel;
        nixosConfigurations = import ./nixosConfigurations toplevel;
      };
    });
}
