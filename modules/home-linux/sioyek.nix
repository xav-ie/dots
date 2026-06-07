{
  flake.modules.homeManager.linux = _: {
    config = {
      # vimified pdf viewer
      programs.sioyek.enable = true;
      xdg.mimeApps.defaultApplications = {
        "application/pdf" = [ "sioyek.desktop" ];
      };
    };
  };
}
