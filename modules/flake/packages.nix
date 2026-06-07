# Custom package set (`#packages.<system>.*`), built from ./../../packages.
{ inputs, ... }:
{
  perSystem =
    {
      lib,
      pkgs,
      system,
      ...
    }:
    let
      # nixpkgs with unfree allowed, for the packages that need it.
      pkgs-unfree = import inputs.nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
    in
    {
      packages = import (inputs.self + "/packages") {
        # ags only builds on linux; null on darwin, where it is unused.
        agsPackages = inputs.ags.packages.${system} or null;
        # virtual-headset mute CLI for the ags bar; linux-only.
        virtual-headset-ctl = inputs.virtual-headset.packages.${system}.virtual-headset-ctl or null;
        # morrow calendar app; linux-only, null on darwin (no output there).
        morrow-pkg = inputs.morrow.packages.${system}.default or null;
        atuin = inputs.atuin.packages.${system}.default;
        generate-kaomoji = inputs.generate-kaomoji.packages.${system}.default;
        # Use regular nixpkgs - most packages are writeNuApplication wrappers
        # that don't need bleeding-edge.
        inherit pkgs;
        # Compute platform from system string - avoids forcing pkgs.stdenv evaluation
        isDarwin = lib.hasSuffix "-darwin" system;
        isLinux = lib.hasSuffix "-linux" system;
        inherit pkgs-unfree;
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
    };
}
