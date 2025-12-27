{ pkgs, ... }:
{
  config = {
    home.packages = [ pkgs.moor ]; # the best pager
    home.sessionVariables = {
      MOAR = "-quit-if-one-screen";
    };
  };
}
