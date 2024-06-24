{ ... }:
{
  xdg = {
    mimeApps.defaultApplications = {
      "application/pdf" = [ "sioyek.desktop" ];
    };
  };
  # vimified pdf viewer
  programs.sioyek.enable = true;
}
