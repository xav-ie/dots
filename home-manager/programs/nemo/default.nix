{ pkgs, ... }:
{
  config = {
    home.packages = with pkgs; [ nemo ];

    xdg.mimeApps.defaultApplications = {
      "inode/directory" = [ "nemo.desktop" ];
      "x-scheme-handler/file" = [ "nemo.desktop" ];
      "application/x-gnome-saved-search" = [ "nemo.desktop" ];
    };
  };
}
