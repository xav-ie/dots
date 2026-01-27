{
  pkgs,
  ...
}:
{
  imports = [ ./globals.nix ];

  config = {
    # Don't use programs.npm.settings - it manages ~/.npmrc which npm needs for auth tokens
    programs.npm.package = pkgs.nodejs;
    programs.npm.settings = { }; # Override default to prevent creating ~/.npmrc

    # Write static config to globalconfig location instead
    # npm reads: project .npmrc -> ~/.npmrc (userconfig) -> ~/.npm/etc/npmrc (globalconfig)
    home.file.".npm/etc/npmrc".text = ''
      prefix=~/.npm
      fund=false
      audit=false
    '';
  };
}
