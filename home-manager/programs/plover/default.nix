{ inputs, pkgs, ... }:
{
  # https://docs.stenokeyboards.com/
  # https://github.com/openstenoproject/plover-flake
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
