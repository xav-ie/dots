# Custom package set (`#packages.<system>.*`), built from ./../../packages.
{ inputs, ... }:
{
  perSystem =
    {
      lib,
      pkgs,
      system,
      writeNuApplication,
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
      # The single definition of the nu-script builder: every module that needs
      # it takes `writeNuApplication` as a perSystem arg, package set included.
      _module.args.writeNuApplication =
        inputs.nuenv.lib.mkNushellScriptApplication pkgs.nushell pkgs.writeTextFile
          pkgs.lib;

      packages = import (inputs.self + "/packages") {
        # ags only builds on linux; null on darwin, where it is unused.
        agsPackages = inputs.ags.packages.${system} or null;
        # virtual-headset mute CLI for the ags bar; linux-only.
        virtual-headset-ctl = inputs.virtual-headset.packages.${system}.virtual-headset-ctl or null;
        # virtual-headset AGS panel, opened from the bar's right-click; linux-only.
        virtual-headset-panel = inputs.virtual-headset.packages.${system}.virtual-headset-panel or null;
        # morrow calendar app; linux-only, null on darwin (no output there).
        morrow-pkg = inputs.morrow.packages.${system}.default or null;
        # ream PDF-tools app; linux-only, null on darwin (no output there).
        ream-pkg = inputs.ream.packages.${system}.default or null;
        # browser-session-mcp (extracted to its own repo); linux-only.
        browser-session-mcp-pkg = inputs.browser-session-mcp.packages.${system}.default or null;
        sketchybar-icons-pkg = inputs.sketchybar-icons.packages.${system}.default or null;
        generate-kaomoji = inputs.generate-kaomoji.packages.${system}.default;
        # uair carries an unmerged PR patch from overlays/default.nix: PR#31's
        # newline-flushed `uairctl listen` for the AGS bar. The package-set pkgs
        # below has no overlays applied, so extend it with them and pull the
        # patched build out.
        inherit ((pkgs.extend (inputs.self.overlays |> builtins.attrValues |> lib.composeManyExtensions)))
          uair
          ;
        # Use regular nixpkgs - most packages are writeNuApplication wrappers
        # that don't need bleeding-edge.
        inherit pkgs;
        # Compute platform from system string - avoids forcing pkgs.stdenv evaluation
        isDarwin = lib.hasSuffix "-darwin" system;
        isLinux = lib.hasSuffix "-linux" system;
        inherit pkgs-unfree;
        pkgs-bleeding = import (inputs.self + "/overlays/_bleeding.nix") {
          inherit (inputs) nixpkgs-bleeding;
          inherit system;
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
        inherit writeNuApplication;
        muscat-pkg = inputs.muscat.packages.${system}.muscat;
        inherit (inputs)
          bun-demincer-src
          clauhist-src
          executor-src
          mcp-atlassian-src
          protonmail-mcp-src
          simulstreaming-src
          zerobrew-src
          ;
        slack-mcp-server-src = inputs.slack-mcp-server;
      };
    };
}
