{ config, lib, ... }:
let
  cfg = config.programs.bat;
in
{
  config = {
    programs.bat = {
      enable = true;
      config = {
        theme = "ansi";
        paging = "always";
        style = "plain";
        wrap = "never";
      };
    };
    home.sessionVariables = lib.mkIf cfg.enable {
      PAGER = lib.getExe cfg.package;
    };
  };
}
