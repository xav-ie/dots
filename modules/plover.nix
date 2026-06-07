# Plover stenography.
# https://docs.stenokeyboards.com/
# https://github.com/openstenoproject/plover-flake
# STKPWHRAO*EUFRPBLGTSDZ
# Seven   Tigers Prowling Hunters *          *     Flew     Past   Leaving Through Dark
# (silly) Kept   While    Ran     *          *     Rapidly  Beasts Glitter Strange Zones.
#                #        Around  Outside.   Eight Unicorns #
{
  # uinput access for character output and serial port for the keyboard.
  flake.modules.nixos.linux =
    { config, lib, ... }:
    {
      options = {
        services.plover = {
          enable = lib.mkEnableOption "Plover stenography support";
        };
      };

      config = lib.mkIf config.services.plover.enable {
        # Add udev rule to allow input group to access /dev/uinput for character output
        services.udev.extraRules = ''
          KERNEL=="uinput", GROUP="input", MODE="0660", OPTIONS+="static_node=uinput"
        '';

        # Add input group for /dev/uinput access and dialout group for serial port access
        users.users."${config.defaultUser}".extraGroups = [
          "input"
          "dialout"
        ];
      };
    };

  # The Plover program itself plus machine/output settings.
  flake.modules.homeManager.common =
    { inputs, pkgs, ... }:
    {
      imports = [
        inputs.plover-flake.homeManagerModules.plover
      ];

      config = {
        programs.plover = {
          enable = true;
          package = inputs.plover-flake.packages.${pkgs.stdenv.hostPlatform.system}.plover-full;

          settings = {
            "Machine Configuration" = {
              machine_type = "Gemini PR";
              auto_start = true;
            };
            "Output Configuration".undo_levels = 100;
          };
        };
      };
    };
}
