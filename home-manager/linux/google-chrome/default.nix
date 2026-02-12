{ pkgs, ... }:
{
  config = {
    programs.google-chrome = {
      enable = true;
      package = pkgs.pkgs-bleeding.google-chrome;
      commandLineArgs = [ ];
    };
  };
}
