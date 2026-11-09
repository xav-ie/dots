# herdr's plugin registry. Upstream's `herdr plugin install|link` mutate
# ~/.config/herdr/plugins.json (a plain JSON array) and build inside a checkout.
# Here each plugin is a nix package and its store path is registered directly,
# so plugins.json is a read-only symlink: `herdr plugin install|link|enable|
# disable` fail, and plugins are declared through this option or not at all.
# Plugin actions run where the herdr server runs, so a plugin that should work
# in `herdr --remote` sessions must be declared on the remote host too.
{
  flake.modules.homeManager.common =
    { config, lib, ... }:
    let
      cfg = config.programs.herdr;
    in
    {
      options.programs.herdr.plugins = lib.mkOption {
        type = lib.types.listOf (lib.types.attrsOf lib.types.anything);
        default = [ ];
        description = ''
          Entries for ~/.config/herdr/plugins.json, in the shape `herdr plugin
          link` writes, with source.kind = "local" since a store path is not a
          checkout herdr may update.
        '';
      };

      config = lib.mkIf (cfg.plugins != [ ]) {
        xdg.configFile."herdr/plugins.json" = {
          text = builtins.toJSON cfg.plugins;
          # herdr writes an empty `[]` here on first start, which would
          # otherwise block activation on every fresh machine.
          force = true;
        };
      };
    };
}
