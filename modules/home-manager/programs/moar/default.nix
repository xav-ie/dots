{ pkgs, ... }:
{
  home.sessionVariables = {
    MOAR = "-quit-if-one-screen";
  };
  home.packages = [ pkgs.moar ]; # the best pager
}
