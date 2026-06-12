# Linux home-manager package set and desktop session config (portals, tray).
{
  flake.modules.homeManager.linux =
    { pkgs, ... }:
    {
      config = {
        home = {
          packages =
            (with pkgs; [
              python3
              ################################
              # in triage - try to minimize this list
              ################################
              asciinema # record shell sessions and share easily
              age # the new PGP
              clipboard-jh # a really awesome clipboard
              home-assistant
              manix
              # nodePackages."webtorrent-cli"
              xidel # like jq but for html and much more advanced.
              # prusa-slicer                # does not launch currently
              python312Packages."adblock"
              subliminal-custom # for mpv autosub script (custom 2.4.0 with knowit)
              xdg-utils # xdg-open, xdg-mime, xdg-email, etc.
              wf-recorder
              # https://github.com/marionebl/svg-term-cli
              # allows asciinema recordings to be exported to svg... this could be
              # pretty indispensable if you would like ANSI escape sequences to be
              # interpreted by GH
              ################################
              # universal utils
              ################################
              cmake
              file # magic number reader
              gcc
              # gnumake # provides `make`, which should already be provided?
              #ninja
              vim
              wget
              ################################
              # user programs
              ################################
              bitwarden-desktop
              ente-desktop # Ente Photos desktop client (broken on Darwin upstream)
              # chromium - configured via programs.chromium below
              # discord
              pavucontrol # audio mixer
              playerctl # play, pause, next
              pulseaudio # provides pactl for volume control
              # qutebrowser
              zoom-us
            ])
            ++ (with pkgs.pkgs-bleeding; [
              # needs latest security releases
              signal-desktop
            ])
            ++ (with pkgs.pkgs-mine; [
              chrome-headless-shell
              mcp-atlassian
              move-active
              record
              record-section
            ]);

          # NVIDIA/Wayland env vars live in the hyprland module — they're only
          # relevant under that graphical session.
          sessionVariables = {
            NH_ELEVATION_PROGRAM = "/run/wrappers/bin/sudo-askpass";
            SUDO_ASKPASS = "${pkgs.pkgs-mine.askpass}/bin/askpass";
            XDG_CONFIG_HOME = "/home/x/.config";
          };
        };
        programs = {
          chromium = {
            enable = true;
            commandLineArgs = [
              "--ignore-gpu-blocklist"
              "--enable-gpu-rasterization"
              "--enable-zero-copy"
              # feature flags updated for Chromium 131+ (old Vaapi* names were renamed)
              # VaapiOnNvidiaGPUs is required for NVIDIA VA-API/NVDEC support
              "--enable-features=AcceleratedVideoDecodeLinuxGL,AcceleratedVideoDecodeLinuxZeroCopyGL,AcceleratedVideoEncoder,VaapiOnNvidiaGPUs,VaapiIgnoreDriverChecks,UseMultiPlaneFormatForHardwareVideo"
              # omit --use-gl/--use-angle to let Chromium pick the default (egl-angle,angle=opengl)
              # opengles is blocked on NVIDIA; vulkan causes render pass stalls with video apps
            ];
          };
          rbw.enable = true; # unofficial bitwarden client
          lazygit.enable = true; # easy git tui
        };

        services = {
          blanket.enable = true;
          # Disabled - causes excessive CPU usage from continuous device discovery
          # Use `bluetoothctl` or `bluetuith` for manual Bluetooth management instead
          # blueman-applet.enable = true;
          network-manager-applet.enable = true;
          hyprpaper = {
            enable = true;
            settings = {
              ipc = "on";
              preload = [ "~/Pictures/desktop.jpg" ];
              wallpaper = [ ",~/Pictures/desktop.jpg" ];
            };
          };
          udiskie = {
            enable = true;
            # The ags bar is the session's SNI host; letting udiskie register its
            # own tray icon races with it ("already registered"). Disable it and
            # surface mounts through the bar's tray instead.
            tray = "never";
          };
        };

        # nm-applet's GTK3 status icon code path on Wayland calls
        # gtk_widget_get_scale_factor() before the widget is fully a
        # GtkWidget; GTK fails the runtime type check, falls back to
        # scale=1, and the icon renders fine. Upstream-known, no fix.
        # Drop the assertion line from journald rather than have it
        # spam every state change.
        systemd.user.services.network-manager-applet.Service.LogFilterPatterns = [
          "~assertion .GTK_IS_WIDGET .widget.. failed"
        ];

        # TODO: somehow make mac support this
        xdg.mimeApps.enable = true;

        # Portal configuration for home-manager
        # When home-manager's Hyprland module (systemd.enable = true) is used,
        # it sets NIX_XDG_DESKTOP_PORTAL_DIR which overrides system portals.
        # We must explicitly include all portals we need here.
        # See: https://github.com/nix-community/home-manager/issues/7124
        xdg.portal = {
          extraPortals = with pkgs; [
            xdg-desktop-portal-gnome
            # gtk owns the FileChooser interface; gnome's backend only exposes
            # Settings off a GNOME session and cannot serve the file picker here.
            xdg-desktop-portal-gtk
            # xdg-desktop-portal-hyprland is automatically added by Hyprland module
          ];
          # Config is set at NixOS level in modules/nixos/hyprland.nix
        };
      };
    };
}
