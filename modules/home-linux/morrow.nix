{
  flake.modules.homeManager.linux =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.pkgs-mine.morrow ];
    };
}
