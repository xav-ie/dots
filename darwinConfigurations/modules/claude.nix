{
  config,
  lib,
  ...
}:
let
  hmConfig = config.home-manager.users.${config.defaultUser};
in
{
  config = lib.mkIf hmConfig.programs.claude.enable {
    homebrew.brews = [ "sox" ];
  };
}
