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
    pinentry.package = pkgs.pinentry-gnome3;
  };

  # Add pinentry-gnome3 to packages on Linux
  home.packages = lib.optionals isLinux [
    pkgs.pinentry-gnome3
  ];
}
