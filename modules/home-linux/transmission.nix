{
  flake.modules.homeManager.linux =
    { pkgs, ... }:
    {
      config = {
        home.packages = [ pkgs.transmission_4-gtk ];
        xdg.mimeApps.defaultApplications = {
          "x-scheme-handler/magnet" = "transmission-gtk.desktop";
        };
      };
    };
}
