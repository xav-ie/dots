# Auto-forwarding of dev-server ports out of a remote herdr session, so
# `herdr --remote praesidium` no longer needs a second terminal holding an
# `ssh -L` open. Split across the two machines by design:
#
#   praesidium (linux) — hosts herdr and the dev servers, runs the plugin, which
#                        discovers loopback listeners owned by pane processes.
#   nox (darwin)       — the connecting machine, runs `hfwd`, which owns the ssh
#                        forwards and the dashboard.
#
# Upstream registers the plugin with `herdr plugin install`, which curls a
# binary into the checkout; here it goes through programs.herdr.plugins
# (plugins.nix) with plugin_root pointed at the store instead.
{
  flake.modules.homeManager = {
    # The connecting side. `hfwd` is what you actually run: `hfwd praesidium`.
    darwin =
      { pkgs, ... }:
      {
        home.packages = [ pkgs.pkgs-mine.herdr-fwd ];
      };

    # The plugin side.
    linux =
      { pkgs, ... }:
      let
        fwd = pkgs.pkgs-mine.herdr-fwd;
        root = "${fwd}/${fwd.pluginRoot}";
      in
      {
        home.packages = [ fwd ];

        # Fields are copied from herdr-plugin.toml; a mismatch only shows as wrong
        # metadata in `herdr plugin list`, since herdr re-reads the manifest at
        # run time.
        programs.herdr.plugins = [
          {
            plugin_id = "herdr.fwd";
            name = "Herdr Fwd";
            version = "0.1.5";
            min_herdr_version = "0.8.0";
            description = "Discover localhost dev servers in remote Herdr panes and request local SSH forwards";
            manifest_path = "${root}/herdr-plugin.toml";
            plugin_root = root;
            enabled = true;
            platforms = [
              "linux"
              "macos"
            ];
            source.kind = "local";
          }
        ];

        # The welcome popup exists to walk you through installing `hfwd` via
        # Homebrew or a curl installer. Nix already did that, so skip straight
        # to the working state instead of having the wizard greet every attach.
        #
        # This lives in herdr's per-plugin config dir, NOT the
        # ~/.config/herdr-fwd/config.toml that docs/plugin.md names — that path
        # is inert; the wizard wrote here. The other two keys are the dashboard's
        # `h` settings, so changing them is a rebuild rather than a keypress
        # (the file is a read-only store symlink).
        xdg.configFile."herdr/plugins/config/herdr.fwd/config.toml".text = ''
          onboarding = false
          after_forward = "space"
          process_tree_depth = 2
        '';
      };
  };
}
