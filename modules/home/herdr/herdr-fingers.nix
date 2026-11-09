# Keyboard link hints (tmux-fingers) for herdr: `prefix+f` labels every path,
# URL, SHA, IP and number in the focused pane; typing a label copies it, with
# Shift it pastes into the pane, with Ctrl it opens. Declared on every host that
# runs a herdr server, so it also works inside `herdr --remote praesidium`.
{
  flake.modules.homeManager.common =
    { pkgs, ... }:
    let
      fingers = pkgs.pkgs-mine.herdr-fingers;
      root = "${fingers}/${fingers.pluginRoot}";
    in
    {
      # Fields copied from herdr-plugin.toml; a mismatch only shows as wrong
      # metadata in `herdr plugin list`, since herdr re-reads the manifest at run
      # time.
      programs.herdr.plugins = [
        {
          plugin_id = "nathan-poncet.herdr-fingers";
          name = "Herdr Fingers";
          inherit (fingers) version;
          min_herdr_version = "0.7.0";
          description = "tmux-fingers for Herdr: type a short hint to copy, paste or open any path, URL, hash or number visible in the pane.";
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
    };
}
