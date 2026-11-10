# Keyboard link hints (tmux-fingers) for herdr. Declared on every host that runs
# a herdr server, so both work inside `herdr --remote praesidium` too:
#   prefix+f        label links, paths, SHAs, IPs, numbers; a label copies it
#   prefix+shift+f  label links only; a label opens it
# Links and paths come from herdr's `pane.links` (herdr_links), so they match
# Ctrl-hover. Opening goes through `herdr terminal open-url`, which opens on the
# machine the client is attached from: the plugin itself runs on the server,
# where `:open:` would launch the browser on that host.
{
  flake.modules.homeManager.common =
    { pkgs, ... }:
    let
      fingers = pkgs.pkgs-mine.herdr-fingers;
      toml = pkgs.formats.toml { };

      # The picked destination arrives on stdin.
      openUrl = pkgs.writeShellApplication {
        name = "herdr-fingers-open-url";
        runtimeInputs = [ pkgs.herdr ];
        text = ''exec herdr terminal open-url "$(cat)"'';
      };

      # Fields copied from herdr-plugin.toml; a mismatch only shows as wrong
      # metadata in `herdr plugin list`, since herdr re-reads the manifest at run
      # time.
      registration = id: name: rootDir: {
        plugin_id = id;
        inherit name;
        inherit (fingers) version;
        min_herdr_version = "0.7.0";
        description = "tmux-fingers for Herdr: type a short hint to copy, paste or open any path, URL, hash or number visible in the pane.";
        manifest_path = "${fingers}/${rootDir}/herdr-plugin.toml";
        plugin_root = "${fingers}/${rootDir}";
        enabled = true;
        platforms = [
          "linux"
          "macos"
        ];
        source.kind = "local";
      };
    in
    {
      programs.herdr.plugins = [
        (registration "nathan-poncet.herdr-fingers" "Herdr Fingers" fingers.pluginRoot)
        (registration "nathan-poncet.herdr-fingers-open" "Herdr Fingers (open)" fingers.openPluginRoot)
      ];

      # Only keys that differ from the plugin's defaults. force: the plugin
      # writes a defaults file here on first run, which would block activation.
      xdg.configFile = {
        "herdr/plugins/config/nathan-poncet.herdr-fingers/config.toml" = {
          force = true;
          source = toml.generate "herdr-fingers.toml" {
            ctrl_action = "${openUrl}/bin/herdr-fingers-open-url";
            # url and path come from herdr instead.
            enabled_builtin_patterns = [
              "diff"
              "digit"
              "git-status"
              "git-status-branch"
              "hex"
              "ip"
              "kubernetes"
              "kubernetes-pod"
              "sha"
              "uuid"
            ];
            herdr_links = "all";
          };
        };
        "herdr/plugins/config/nathan-poncet.herdr-fingers-open/config.toml" = {
          force = true;
          source = toml.generate "herdr-fingers-open.toml" {
            ctrl_action = "${openUrl}/bin/herdr-fingers-open-url";
            enabled_builtin_patterns = [ ];
            herdr_links = "urls";
            main_action = "${openUrl}/bin/herdr-fingers-open-url";
            shift_action = ":copy:";
          };
        };
      };
    };
}
