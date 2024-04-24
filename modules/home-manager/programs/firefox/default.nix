{ lib, pkgs, ... }:
let
  merge = lib.foldr (a: b: a // b) { };
in
{
  firefox = {
    enable = true;
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

          /* ~~~~~~~~ Autohiding styles ~~~~~~~~~ */
          :root {
           --sidebar-hover-width: 36px;
           --sidebar-visible-width: 190px;
           --sidebar-debounce-delay: 50ms;

          }
          #sidebar-box {
           display: grid !important;
           min-width: var(--sidebar-hover-width) !important;
           max-width: var(--sidebar-hover-width) !important;
           overflow: visible !important;
           height: 100% !important;
           min-height: 100% !important;
           max-height: 100% !important;
          }
          #sidebar {
           height: 100% !important;
           width: var(--sidebar-hover-width) !important;
           z-index: 200 !important;
           position: absolute !important;
           transition: width 150ms var(--sidebar-debounce-delay) ease !important;
           min-width: 0 !important;
          }
          #sidebar:hover {
           width: var(--sidebar-visible-width) !important;
          }
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
}
