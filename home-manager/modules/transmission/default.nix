{ pkgs, ... }:
{
  config = {
    home.packages = [ pkgs.transmission_4-gtk ];
    xdg.mimeApps.defaultApplications = {
      "x-scheme-handler/magnet" = "transmission-gtk.desktop";
    };
  };
}
