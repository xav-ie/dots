{ pkgs, ... }:
{
  home.packages = [ pkgs.transmission_3-gtk ];
  xdg.mimeApps.defaultApplications =
    let
      # TODO: make this more rigorous?
      # I am not sure if this is the right way to do this
      # torrent-client = "${pkgs.transmission-gtk}/share/applications/transmission-gtk.desktop";

      torrent-client = "transmission-gtk.desktop";
    in
    {
      "x-scheme-handler/magnet" = torrent-client;
    };
}
