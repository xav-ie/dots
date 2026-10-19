{ inputs, ... }:
{
  flake.modules.darwin.macos =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      hmConfig = config.home-manager.users.${config.defaultUser};
      managedSettings = import ./_managed-settings.nix {
        inherit inputs pkgs;
        inherit (hmConfig.home) homeDirectory;
      };
    in
    {
      config = lib.mkIf hmConfig.programs.claude.enable {
        homebrew.brews = [ "sox" ];

        # nix-darwin's environment.etc can't reach /Library, so install the
        # policy file from activation instead.
        system.activationScripts.postActivation.text = ''
          install -D -m 644 ${managedSettings} \
            "/Library/Application Support/ClaudeCode/managed-settings.json"
        '';
      };
    };
}
