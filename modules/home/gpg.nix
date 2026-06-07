{
  flake.modules.homeManager.common =
    { lib, pkgs, ... }:
    let
      inherit (pkgs.stdenv) isLinux;
    in
    {
      programs.gpg = {
        enable = true;
      };

      services.gpg-agent = {
        enable = true;
        enableSshSupport = true;
      }
      // lib.optionalAttrs isLinux {
        pinentry.package = pkgs.pkgs-mine.pinentry-auto;
      };

      home.packages = lib.optionals isLinux [
        pkgs.pkgs-mine.pinentry-auto
      ];
    };
}
