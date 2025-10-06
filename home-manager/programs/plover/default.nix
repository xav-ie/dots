{ inputs, pkgs, ... }:
{
  # https://docs.stenokeyboards.com/
  # https://github.com/openstenoproject/plover-flake
  # STKPWHRAO*EUFRPBLGTSDZ
  # Seven   Tigers Prowling Hunters *          *     Flew     Past   Leaving Through Dark
  # (silly) Kept   While    Ran     *          *     Rapidly  Beasts Glitter Strange Zones.
  #                #        Around  Outside.   Eight Unicorns #
  imports = [
    inputs.plover-flake.homeManagerModules.plover
  ];

  config = {
    programs.plover = {
      enable = true;
      package = inputs.plover-flake.packages.${pkgs.system}.plover-full;

      settings = {
        "Machine Configuration" = {
          machine_type = "Gemini PR";
          auto_start = true;
        };
        "Output Configuration".undo_levels = 100;
      };
    };
  };
}
