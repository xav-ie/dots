{
  # lib,
  pkgs,
  ...
}:
# let
#   merge = lib.foldr (a: b: a // b) { };
#   inherit ((import ../../../lib/fonts.nix { inherit lib pkgs; })) fonts;
# in
{
  config = {
    home.packages = [ pkgs.firefoxpwa ];
    programs.firefox = {
      enable = true;
      package = pkgs.pkgs-bleeding.firefox;
      nativeMessagingHosts = [ pkgs.firefoxpwa ];
      # setting this prevents dynamic profile configuration...
      # We should make this so it generates a program that attempts to set
      # profile settings instead
      # profiles.x = {
      #   id = 0;
      #   isDefault = true;
      #   settings = merge [
      #     (import ./annoyances.nix)
      #     (import ./settings.nix { inherit fonts; })
      #   ];
      #   userChrome = # css
      #     ''
      #       /* ########  Sidetabs Styles  ######### */
      #
      #       /* ~~~~~~~~ Hidden elements styles ~~~~~~~~~ */
      #       #TabsToolbar {
      #       	display: none !important;
      #       }
      #       #titlebar {
      #       	display: none !important;
      #       }
      #       #sidebar-header {
      #       	display: none !important;
      #       }
      #       /* ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ */
      #       * {
      #         font-family: ${fonts.name "sans"}, ${fonts.name "emoji"} !important;
      #       }
      #
      #       /* #################################### */
      #     '';
      #
      #   extensions.packages = with pkgs.nur.repos.rycee.firefox-addons; [
      #     bitwarden
      #     ublock-origin
      #     vimium-c
      #     newtab-adapter
      #     videospeed
      #   ];
      # };
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
