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
            # dockerfmt is broken on Darwin; Dockerfiles are excluded there below.
            dockerfmt.enable = pkgs.stdenv.isLinux;
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
                "*.mjs"
                "*.mts"
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
              "**/*.entitlements"
              "**/*.env"
              "**/*.modulemap"
              "**/*.txt"
              "**/.gitignore"
              "**/.inputrc"
              "**/.npmrc"
              "**/.terraform.lock.hcl"
              "**/Cargo.lock"
              "*.awk"
              "*.conf"
              "*.nu" # formatter is borked
              "*.patch"
              "*.scpt" # no standard formatter for AppleScript
              "*.svg" # no standard formatter
              ".git-blame-ignore-revs"
              ".gitignore"
              "flake.lock"
              "secrets/*.yaml" # sops has its own formatter
            ]
            ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [
              "**/Dockerfile" # dockerfmt broken on Darwin
            ];
          };
        };
    };
}
