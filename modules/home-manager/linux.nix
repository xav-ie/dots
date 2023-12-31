{
  pkgs,
  pwnvim,
  lib,
  ...
} @ inputs: let
  merge = lib.foldr (a: b: a // b) {};
in {
  home = {
    packages = with pkgs; [
      ################################
      # in triage - try to minimize this list
      ################################
      asciinema # record shell sessions and share easily
      age # the new PGP
      blesh # bash extensions
      cliphist
      clipboard-jh # a really awesome clipboard
      ctpv # lf previews, very buggy
#      cudaPackages.cuda_cccl # I wish hardware acceleration would work :/
#      cudaPackages.cudatoolkit
#      cudaPackages.cudnn
      himalaya # email
      hstr
      manix
      nodePackages."webtorrent-cli"
      xidel # like jq but for html and much more advanced.

    ];
    # The state version is required and should stay at the version you
    # originally installed.
    stateVersion = "23.11";
    sessionVariables = {
    };
  };
  programs = {
    firefox = {
      enable = true;
      profiles.x = {
        id = 0;
        isDefault = true;
        settings = merge [
          (import ./programs/firefox/annoyances.nix)
          (import ./programs/firefox/settings.nix)
        ];
        userChrome = ''
          /* hides the native tabs */
          #TabsToolbar {
            visibility: collapse;
          }
          #titlebar {
            visibility: collapse;
          }
          #sidebar-header {
            visibility: collapse !important;
          }
        '';
        extensions = with pkgs.nur.repos.rycee.firefox-addons; [
          bitwarden
          ublock-origin
          vimium-c
          sidebartabs
          newtab-adapter
          videospeed
        ];
      };
    };
  };

  xdg.mimeApps.defaultApplications = {
    "text/plain" = ["qutebrowser.desktop"];
    "application/pdf" = ["sioyek.desktop"];
    "image/*" = ["sxiv.desktop"];
    "video/*" = ["mpv.desktop"];
    "text/html" = ["qutebrowser.desktop"];
    "x-scheme-handler/http" = ["qutebrowser.desktop"];
    "x-scheme-handler/https" = ["qutebrowser.desktop"];
    "x-scheme-handler/ftp" = ["qutebrowser.desktop"];
    "application/xhtml+xml" = ["qutebrowser.desktop"];
    "application/xml" = ["qutebrowser.desktop"];
  };
  # Nicely reload system units when changing configs
  systemd.user.startServices = "sd-switch";

  gtk = {
    enable = true;
    theme.name = "adw-gtk3";
    cursorTheme.name = "Bibata-Modern-Ice";
    iconTheme.name = "GruvboxPlus";
  };
}
