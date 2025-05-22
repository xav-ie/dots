{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  merge = lib.foldr (a: b: a // b) { };
in
{
  config = {
    programs.firefox = {
      enable = true;
      package = inputs.firefox-nixpkgs.legacyPackages.${pkgs.system}.firefox;
      profiles.x = {
        id = 0;
        isDefault = true;
        settings = merge [
          (import ./annoyances.nix)
          (import ./settings.nix)
        ];
        userChrome = # css
          ''
            /* ########  Sidetabs Styles  ######### */

            /* ~~~~~~~~ Hidden elements styles ~~~~~~~~~ */
            #TabsToolbar {
            	display: none !important;
            }
            #titlebar {
            	display: none !important;
            }
            #sidebar-header {
            	display: none !important;
            }
            /* ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ */

            /* #################################### */
          '';
        # TODO: move to declarative set-up
        # extensions = with pkgs.nur.repos.rycee.firefox-addons; [
        #   bitwarden
        #   ublock-origin
        #   vimium-c
        #   newtab-adapter
        #   videospeed
        # ];
      };
    };
    home.sessionVariables = {
      BROWSER = "firefox";
    };
    xdg.mimeApps.defaultApplications =
      let
        browser = "firefox.desktop";
      in
      {
        "application/xhtml+xml" = browser;
        "application/xml" = browser;
        "image/*" = browser;
        "text/html" = browser;
        "text/plain" = browser;
        "x-scheme-handler/ftp" = browser;
        "x-scheme-handler/http" = browser;
        "x-scheme-handler/https" = browser;
      };
  };
}
