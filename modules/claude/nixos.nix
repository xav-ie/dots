{ inputs, ... }:
{
  flake.modules.nixos.linux =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      hmConfig = config.home-manager.users.${config.defaultUser};
    in
    {
      config = lib.mkIf hmConfig.programs.claude.enable {
        environment.etc."claude-code/managed-settings.json".source = import ./_managed-settings.nix {
          inherit inputs pkgs;
          inherit (hmConfig.home) homeDirectory;
        };
      };
    };
}
