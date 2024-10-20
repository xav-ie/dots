{ pkgs, ... }:
{
  config = {
    home.packages = [ pkgs.moar ]; # the best pager
    home.sessionVariables = {
      MOAR = "-quit-if-one-screen";
    };
  };
}
