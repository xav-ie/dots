{
  flake.modules.darwin.macos =
    {
      config,
      inputs,
      lib,
      pkgs,
      ...
    }:
    {
      imports = [
        inputs.nix-homebrew.darwinModules.nix-homebrew
      ];

      config = {
        # https://github.com/zhaofengli/nix-homebrew/issues/5
        # You must tell nix-darwin to just inherit the same taps as nix-homebrew
        homebrew.taps = config.nix-homebrew.taps |> builtins.attrNames;

        nix-homebrew = {
          # Install Homebrew under the default prefix
          enable = true;

          # preview ruby_4_0 reports gem ABI "4.0.0+1" but brew vendors its gems
          # under "4.0.0", so brew looks in a missing dir and won't boot. Add the
          # real vendored gem paths to $LOAD_PATH. Drop when ruby_4_0 is stable.
          package =
            let
              # Single source of truth for HOMEBREW_VERSION: the brew-src tag.
              brewVersion = (builtins.fromJSON (builtins.readFile ../../flake.lock)).nodes.brew-src.original.ref;
              injectLoadPaths =
                pkgs.writeText "brew-vendor-loadpath.rb" # ruby
                  ''
                    setup = ARGV[0]
                    bundle_root = File.expand_path(File.join(File.dirname(setup), ".."))
                    ruby_dir = File.join(bundle_root, "ruby")
                    # Expect exactly one vendored api dir; >1 (or a stray +N dir) would
                    # make Dir.children order-dependent, 0 means the layout changed.
                    candidates = Dir.children(ruby_dir).select { |d| File.directory?(File.join(ruby_dir, d, "gems")) }
                    raise "expected exactly one vendored ruby dir under #{ruby_dir}, found #{candidates.inspect}" unless candidates.length == 1
                    real = candidates.first
                    # Fail the build if a native runtime gem ever appears -- pure-Ruby
                    # load-path injection can't safely stand in for a real ABI match.
                    raise "vendored bundle gained a native extensions/ dir; build gems against pkgs.ruby_4_0" if Dir.exist?(File.join(ruby_dir, real, "extensions"))
                    subs = File.readlines(setup).filter_map do |line|
                      m = line.match(%r{ruby_api_version\}/(gems/[^"]+)"})
                      next unless m
                      m[1] if File.directory?(File.join(ruby_dir, real, m[1]))
                    end.uniq
                    raise "matched zero vendored gems in #{setup} -- brew setup.rb format changed?" if subs.empty?
                    File.open(setup, "a") do |f|
                      f.puts ""
                      subs.each do |sub|
                        f.puts "$:.unshift File.expand_path(\"\#{__dir__}/../ruby/#{real}/#{sub}\")"
                      end
                    end
                  '';
            in
            (pkgs.runCommandLocal "brew-${brewVersion}" { } ''
              cp -r ${inputs.brew-src} $out
              chmod -R u+w "$out/Library/Homebrew/vendor/bundle"
              ${pkgs.ruby_4_0}/bin/ruby ${injectLoadPaths} \
                "$out/Library/Homebrew/vendor/bundle/bundler/setup.rb"
            '')
            // {
              version = brewVersion;
            };
          # TODO: Replace with zerobrew once Brewfile support lands
          # - https://github.com/lucasgelfond/zerobrew/issues/97 (Brewfile support)
          # - https://github.com/lucasgelfond/zerobrew/issues/56 (Cask support)
          # package = pkgs.pkgs-mine.zerobrew;
          # Apple Silicon Only: Also install Homebrew under the default Intel prefix for Rosetta 2
          enableRosetta = true;
          # User owning the Homebrew prefix
          user = config.defaultUser;
          # Optional: Declarative tap management
          taps = {
            "homebrew/homebrew-core" = inputs.homebrew-core;
            "homebrew/homebrew-cask" = inputs.homebrew-cask;
            "homebrew/homebrew-bundle" = inputs.homebrew-bundle;
          };
          # Optional: Enable fully-declarative tap management
          # With mutableTaps disabled, taps can no longer be added imperatively with `brew tap`.
          mutableTaps = false;
        };

        environment.systemPackages = lib.optionals (config.homebrew.masApps ? "Tailscale") [
          (pkgs.writeShellApplication {
            name = "tailscale";
            meta.description = "create a symlink to the tailscale binary provided by MacOS app";
            text = ''
              /Applications/Tailscale.app/Contents/MacOS/Tailscale "$@"
            '';
          })
        ];
      };
    };
}
