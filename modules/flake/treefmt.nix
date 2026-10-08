# treefmt formatter configuration (`treefmt` / `nix fmt`).
{ inputs, ... }:
{
  perSystem =
    {
      config,
      pkgs,
      system,
      ...
    }:
    {
      treefmt =
        { options, ... }:
        let
          glsl_analyzer = pkgs.glsl_analyzer.overrideAttrs (_oldAttrs: {
            src = inputs.glsl_analyzer;
            # The `format` fork's sources use the 0.15 unmanaged-by-default
            # std.ArrayList, so neither nixpkgs' own zig_0_14 pin nor the
            # current `pkgs.zig` compiles it. Pin 0.15 explicitly.
            nativeBuildInputs = [ pkgs.zig_0_15.hook ];
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

          # Recursive JSON key sort; prettier still owns whitespace style.
          jsonSortKeys = pkgs.writeShellApplication {
            name = "json-sort-keys";
            runtimeInputs = [ pkgs.jq ];
            text = ''
              for f in "$@"; do
                jq --sort-keys . "$f" >"$f.tmp" && mv "$f.tmp" "$f"
              done
            '';
          };

          jsonSortKeysFormatterModule =
            { mkFormatterModule, ... }:
            {
              imports = [
                (mkFormatterModule {
                  name = "json-sort-keys";
                  mainProgram = "json-sort-keys";
                  includes = [ "modules/claude/settings.json" ];
                })
              ];
            };

          # Custom Nushell formatter module (treefmt-nix has no nufmt yet)
          nufmtFormatterModule =
            { mkFormatterModule, ... }:
            {
              imports = [
                (mkFormatterModule {
                  name = "nufmt";
                  mainProgram = "nufmt";
                  includes = [ "*.nu" ];
                })
              ];
            };
        in
        {
          imports = [
            glslFormatterModule
            goModFormatterModule
            jsonSortKeysFormatterModule
            nufmtFormatterModule
          ];

          programs = {
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
            # dockerfmt is broken on Darwin; Dockerfiles are excluded there below.
            dockerfmt.enable = pkgs.stdenv.hostPlatform.isLinux;
            glsl_analyzer = {
              enable = true;
              package = glsl_analyzer;
            };
            json-sort-keys = {
              enable = true;
              package = jsonSortKeys;
            };
            just.enable = true;
            kdlfmt.enable = true;
            go-mod-fmt.enable = true;
            gofmt.enable = true;
            nixfmt.enable = true;
            nufmt = {
              enable = true;
              package = inputs.nufmt.packages.${system}.default;
            };
            prettier = {
              enable = true;
              package = config.packages.prettier-with-toml;
              includes = options.programs.prettier.includes.default ++ [
                "*.cfg"
                "*.mjs"
                "*.mts"
                "*.toml"
              ];
            };
            ruff.enable = true;
            rustfmt.enable = true;
            shfmt.enable = true;
            statix.enable = true;
            swift-format.enable = true;
          };
          settings = {
            # Sort before prettier so prettier has the final say on style.
            formatter.json-sort-keys.priority = -1;
            on-unmatched = "fatal";
            excludes = [
              "**/*.entitlements"
              "**/*.env"
              "**/*.modulemap"
              "**/*.txt"
              "**/.gitignore"
              "**/.inputrc"
              "**/.npmrc"
              "**/.terraform.lock.hcl"
              "**/Cargo.lock"
              "**/uv.lock"
              "*.age" # encrypted
              "*.awk"
              "*.conf"
              "*.nuon" # data/config format, no formatter
              "*.patch"
              "*.scpt" # no standard formatter for AppleScript
              "*.svg" # no standard formatter
              ".git-blame-ignore-revs"
              ".gitignore"
              "flake.lock"
              "modules/home-darwin/claude-desktop/claude_desktop_config.json"
              "secrets/*.json" # sops managed
              "secrets/*.yaml" # sops has its own formatter
            ]
            # Binary image/icon assets. `on-unmatched = "fatal"` means any file
            # no formatter claims fails the whole run, so these are listed by
            # extension rather than path. `*.svg` is text and excluded above.
            ++ [
              "*.icns"
              "*.ico"
              "*.jpeg"
              "*.jpg"
              "*.png"
              "*.webp"
            ]
            ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
              "**/Dockerfile" # dockerfmt broken on Darwin
            ];
          };
        };
    };
}
