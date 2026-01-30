{
  config,
  pkgs,
  ...
}:
{
  imports = [ ./globals.nix ];

  config = {
    # Don't use programs.npm.settings - it manages ~/.npmrc which npm login needs to modify
    programs.npm.package = pkgs.nodejs;
    programs.npm.settings = { };

    # Tell npm to read globalconfig from custom location
    home.sessionVariables.NPM_CONFIG_GLOBALCONFIG = "${config.home.homeDirectory}/.npm/etc/npmrc";

    # Write static config to globalconfig location
    home.file.".npm/etc/npmrc".text = builtins.readFile ./.npmrc;
  };
}
