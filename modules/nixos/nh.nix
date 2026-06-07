{
  flake.modules.nixos.linux =
    { config, ... }:
    {
      config.programs.nh = {
        enable = true;
        clean.enable = true;
        clean.extraArgs = "--keep-since 7d --keep 20";
        flake = "/home/${config.defaultUser}/Projects/dots";
      };
    };
}
