{
  config,
  inputs,
  lib,
  osConfig,
  pkgs,
  ...
}:
let
  cfg = config.programs.hyprland;
  barCfg = config.programs.ags-bar;
  # Same `sans` (Inter) the pickers/bar use, so hyprlock tracks the system font.
  inherit ((import ../../../lib/fonts.nix { inherit lib pkgs; })) fonts;

  # Today/Tomorrow forecast for the lock-screen label: each day is a header plus
  # a "rain% icon hi/lo desc" row. Same source (wttr.in Boston, Fahrenheit) and
  # weatherCode→glyph mapping as the notification-center Weather card, so the two
  # stay visually consistent.
  hyprlock-weather = pkgs.writeNuApplication {
    name = "hyprlock-weather";
    text = ''
      # wttr.in weatherCode → Nerd Font (nf-weather) glyph codepoint, matching
      # the symbolic-icon buckets the notification-center Weather card uses.
      let icon_of = {|code|
        if $code == 113 { "e30d" # day_sunny
        } else if $code == 116 { "e302" # day_cloudy
        } else if $code in [119 122] { "e312" # cloudy
        } else if $code in [143 248 260] { "e313" # fog
        } else if $code in [200 386 389 392 395] { "e31d" # thunderstorm
        } else if $code in [179 227 230 323 326 329 332 335 338 368 371] { "e31a" # snow
        } else if $code >= 176 { "e319" # showers
        } else { "e302" }
      }
      try {
        let j = (http get --max-time 10sec 'https://wttr.in/Boston?format=j1' | from json)
        let cur = $j.current_condition.0
        # Today uses the live current condition; tomorrow the ~midday hourly
        # entry (3-hourly → index 4 ≈ 12:00). Rain is the day's peak chance.
        let mk = {|d live|
          # wttr.in sometimes truncates the current day's hourly array, so guard
          # the midday lookup; seed the rain max so an empty list can't throw.
          let hourly = ($d.hourly | default [])
          let src = (if $live { $cur } else { $hourly | get -o 4 | default ($hourly | last) })
          {
            icon: (char -u (do $icon_of ($src.weatherCode | into int)))
            rain: ($hourly | each {|h| $h.chanceofrain | into int } | append 0 | math max)
            hi: $d.maxtempF
            lo: $d.mintempF
            desc: ($src.weatherDesc.0.value | str trim)
          }
        }
        let days = [(do $mk $j.weather.0 true) (do $mk $j.weather.1 false)]
        # Description column fits the wider of the two days, no fixed slack.
        let dw = ($days | each {|x| $x.desc | str length } | math max)
        # Right-align each fixed-width field so columns line up between the
        # two rows while the whole block stays flush-right (text_align=right);
        # the condition glyph is doubled and dropped via a pango <span>.
        let fmt = {|x|
          let rainf = ($"(char -u e371)($x.rain)%" | fill -a r -w 5)
          let temp = ($"($x.hi)°/($x.lo)°" | fill -a l -w 8)
          let desc = ($x.desc | fill -a r -w $dw)
          $"($rainf)   <span size='200%' rise='-19000'>($x.icon)</span>($temp) ($desc)"
        }
        # Headers in Inter ExtraLight (matching the clock/date module); data in
        # mono. The leading zero-width space is load-bearing: hyprgraphics
        # inserts a scale=1 attr over [0, END] after parsing markup, which
        # clobbers any markup scale starting at index 0 — so the first header's
        # size='150%' is lost unless something unscaled occupies index 0.
        let head = {|t| $"<span font='${fonts.name "sans"} ExtraLight' size='150%'>($t)</span>" }
        print $"(char -u '200b')(do $head Today)\n(do $fmt ($days | get 0))\n\n(do $head Tomorrow)\n(do $fmt ($days | get 1))"
      } catch {
        # Network down (common right after wake), rate-limit, or bad payload:
        # degrade to a single line instead of a blank region on the lock screen.
        print $"(char -u '200b')<span font='${fonts.name "sans"} ExtraLight' size='150%'>Weather unavailable</span>"
      }
    '';
  };
in
{
  imports = [
    ./hyprshade
  ];

  options.programs.hyprland = {
    gapsNumeric = lib.mkOption {
      default = 10;
      type = lib.types.ints.unsigned;
    };
    borderSizeNumeric = lib.mkOption {
      default = 4;
      type = lib.types.ints.unsigned;
    };
  };

  config = {
    # There is lots of weird edge cases listed here:
    # https://wiki.hyprland.org/Nvidia/#how-to-get-hyprland-to-possibly-work-on-nvidia
    home.sessionVariables = {
      GBM_BACKEND = "nvidia-drm";
      LIBVA_DRIVER_NAME = "nvidia";
      MOZ_DISABLE_RDD_SANDBOX = "1";
      NIXOS_OZONE_WL = "1";
      NVD_BACKEND = "direct"; # github:elFarto
      WLR_NO_HARDWARE_CURSORS = "1";
      WLR_RENDERER_ALLOW_SOFTWARE = "1";
      XCURSOR_SIZE = "24";
      XDG_SESSION_TYPE = "wayland";
      __GLX_VENDOR_LIBRARY_NAME = "nvidia";
    };

    home.pointerCursor = {
      name = "phinger-cursors-dark";
      package = pkgs.phinger-cursors;
      size = 36;
      gtk.enable = true;
      hyprcursor.enable = true;
      hyprcursor.size = 36;
    };

    home.packages = with pkgs; [
      pkgs-mine.pickers
      hyprshot
      libnotify
      libva
      libva-utils # hardware video acceleration
      polkit_gnome # just a GUI askpass
      waypipe
      wl-clipboard
    ];

    programs = {
      hyprlock = {
        enable = true;
        settings = {
          "$font" = fonts.name "sans";

          general = {
            hide_cursor = true;
          };

          animations = {
            enabled = true;
            bezier = "linear, 1, 1, 0, 0";
            animation = [
              "fadeIn, 1, 5, linear"
              "fadeOut, 1, 5, linear"
              "inputFieldDots, 1, 2, linear"
            ];
          };

          background = {
            monitor = "";
            path = "screenshot";
            blur_passes = 3;
          };

          input-field = {
            # monitor =
            size = "20%, 5%";
            outline_thickness = 3;
            inner_color = "rgba(26, 23, 38, 0.55)"; # purple-tinted fill (#1a1726)

            # Spotlight palette: lavender accent idle, green while checking, red on
            # fail, amber while Caps Lock is on.
            outer_color = "rgba(bb9af7ee) rgba(9d7cd8ee) 45deg";
            check_color = "rgba(9ece6aee) rgba(bb9af7ee) 120deg";
            fail_color = "rgba(f7768eee) rgba(ff0066ee) 40deg";
            capslock_color = "rgba(e0af68ee) rgba(d9a05bee) 45deg";

            font_color = "rgb(242, 238, 251)"; # fg (#f2eefb)
            fade_on_empty = false;
            rounding = 15;

            font_family = "$font";
            placeholder_text = "Input password...";
            fail_text = "$PAMFAIL";

            # uncomment to use a letter instead of a dot to indicate the typed password
            # dots_text_format = *
            # dots_size = 0.4
            dots_spacing = 0.3;

            # uncomment to use an input indicator that does not show the password length (similar to swaylock's input indicator)
            # hide_input = true

            position = "0, -20";
            halign = "center";
            valign = "center";
          };

          label = [
            # TIME
            {
              monitor = "";
              # 12-hour clock, e.g. "9:41 PM". Thin weight via a static
              # font_family: hyprlock parses it once with
              # pango_font_description_from_string, where "Inter Thin" selects the
              # Thin face (the bar's CSS font-weight is a separate mechanism).
              text = ''cmd[update:1000] date +"%-I:%M %p"'';
              color = "rgb(242, 238, 251)"; # fg (#f2eefb)
              font_size = 180;
              font_family = "${fonts.name "sans"} Thin";

              position = "30, 0";
              halign = "left";
              valign = "top";
            }

            # DATE
            {
              monitor = "";
              text = ''cmd[update:60000] date +"%A, %d %B %Y"''; # update every 60 seconds
              color = "rgb(242, 238, 251)"; # fg (#f2eefb)
              font_size = 50;
              font_family = "$font";

              position = "30, -300";
              halign = "left";
              valign = "top";
            }

            # WEATHER (top right) — mirrors the notification-center card.
            {
              monitor = "";
              text = "cmd[update:900000] ${lib.getExe hyprlock-weather}"; # refresh every 15 min
              color = "rgb(242, 238, 251)"; # fg (#f2eefb)
              font_size = 38;
              # Mono Nerd Font: single-cell glyphs keep the columns aligned and
              # carry the nf-weather icons; ExtraLight for a feather-light look.
              # Headers override to Inter Thin via inline pango markup.
              font_family = "CaskaydiaCove Nerd Font Mono ExtraLight";
              text_align = "right";

              position = "-20, -22";
              halign = "right";
              valign = "top";
            }
          ];

        };
      };
    };

    services = {
      hypridle = {
        enable = true;
        settings = {
          general = {
            # also lock before systemd suspend
            before_sleep_cmd = "loginctl lock-session";
            # prevent having to press key twice
            after_sleep_cmd = "hyprctl dispatch dpms on";
            lock_cmd = "${config.programs.hyprlock.package}/bin/hyprlock --grace 10 || true";
          };

          listener = [
            {
              timeout = 900;
              on-timeout = "loginctl lock-session";
            }
            {
              # Enable DND before DPMS off to prevent notifications from waking the monitor
              timeout = 1170;
              on-timeout = "${lib.getExe' pkgs.pkgs-mine.notification-center "notifctl"} --dnd-on";
              on-resume = "${lib.getExe' pkgs.pkgs-mine.notification-center "notifctl"} --dnd-off";
            }
            {
              timeout = 1200;
              on-timeout = "hyprctl dispatch dpms off";
              on-resume = "hyprctl dispatch dpms on";
            }
          ]
          ++ lib.optionals osConfig.services.power-save.enable [
            {
              # After 30 minutes idle, enter power save mode
              timeout = 1800;
              on-timeout = "${pkgs.systemd}/bin/systemctl start power-save-enter.service";
              on-resume = "${pkgs.systemd}/bin/systemctl start power-save-exit.service";
            }
          ];
        };
      };

    };

    wayland.windowManager.hyprland =
      let
        inherit (inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}) hyprland;
        inherit (cfg) borderSizeNumeric gapsNumeric;
        barHeightNumeric = barCfg.barHeight;
        gapAndBorderNumeric = gapsNumeric + borderSizeNumeric;
        barSpaceNumeric = gapAndBorderNumeric + barHeightNumeric - borderSizeNumeric;
        windowTopNumeric = gapAndBorderNumeric + barSpaceNumeric;
        windowLeftNumeric = gapsNumeric + borderSizeNumeric;

        gaps = toString gapsNumeric;
        windowLeft = toString windowLeftNumeric;
        windowTop = toString windowTopNumeric;

        pipHeight = 324;
        move-active = "${pkgs.pkgs-mine.move-active}/bin/move-active";
        virtual-headset-ctl = "${
          inputs.virtual-headset.packages.${pkgs.stdenv.hostPlatform.system}.virtual-headset-ctl
        }/bin/virtual-headset-ctl";
      in
      {
        enable = true;
        package = hyprland;
        systemd.enable = true;
        xwayland.enable = true;
        settings = {
          env = [
            "XCURSOR_THEME,${config.home.pointerCursor.name}"
            "XCURSOR_SIZE,${builtins.toString config.home.pointerCursor.size}"
            "HYPRCURSOR_THEME,${config.home.pointerCursor.name}"
            "HYPRCURSOR_SIZE,${builtins.toString config.home.pointerCursor.size}"
          ];

          # For all categories, see https://wiki.hyprland.org/Configuring/Variables/
          input = {
            kb_layout = "us";
            # kb_variant =
            # kb_model =
            # kb_rules =
            # probably don't do this
            # kb_options = caps:swapescape
            follow_mouse = 1;

            touchpad = {
              natural_scroll = "yes";
              scroll_factor = 0.8;
            };
            # -1.0 - 1.0, 0 means no modification.
            sensitivity = 0.0;
          };
          general = {
            # See https://wiki.hyprland.org/Configuring/Variables/ for more
            gaps_in = toString (gapsNumeric / 2);
            gaps_out = gaps;
            border_size = toString borderSizeNumeric;

            # darker/saturated take on packages/pickers accent ($accent #bb9af7)
            "col.inactive_border" = "rgb(3a2e5e)";
            "col.active_border" = "rgb(7c5cba)";

            layout = "dwindle";
          };

          decoration = {
            # See https://wiki.hyprland.org/Configuring/Variables/ for more
            # make it match border-width for ultimate roundness
            rounding = 4;

            blur = {
              enabled = true;
              size = 8;
              passes = 3;
            };

            shadow = {
              enabled = false;
            };
          };

          dwindle = {
            # See https://wiki.hyprland.org/Configuring/Dwindle-Layout/ for more
            pseudotile = "yes"; # master switch for pseudotiling. Enabling is bound to mainMod + P in the keybinds section below
            preserve_split = "yes"; # you probably want this
          };

          master = {
            # See https://wiki.hyprland.org/Configuring/Master-Layout/ for more
            new_status = "master"; # "slave"
          };

          gestures = {
            # See https://wiki.hyprland.org/Configuring/Variables/ for more
            # workspace_swipe = "on";
            workspace_swipe_distance = 300;
            workspace_swipe_min_speed_to_force = 0;
            workspace_swipe_cancel_ratio = 0;
          };

          misc = {
            animate_manual_resizes = true;
            animate_mouse_windowdragging = true;
            focus_on_activate = true;
          };

          cursor = {
            hide_on_key_press = true;
          };

          debug = {
            # damage_tracking = false
          };

          # Execute your favorite apps at launch.
          # hyprpaper is started via its own home-manager systemd user service —
          # no need to launch it here.
          exec-once = [
            "${lib.getExe' pkgs.wl-clipboard "wl-paste"} --type text --watch cliphist store"
            "${lib.getExe' pkgs.wl-clipboard "wl-paste"} --type image --watch cliphist store"
            # Pre-warm the spotlight launcher so the picker keybinds open
            # instantly (it stays resident and just switches/toggles its mode).
            "${pkgs.pkgs-mine.pickers}/bin/spotlight --daemon"
            "[workspace 2 silent] ${config.programs.firefox.package}/bin/firefox"
            "[workspace 1 silent] ${config.programs.ghostty.package}/bin/ghostty"
          ];

          animations = {
            enabled = "yes";

            # Some default animations, see https://wiki.hyprland.org/Configuring/Animations/ for more
            bezier = [
              "myBezier, 0.05, 0.9, 0.1, 1.05"
              "overshot,0.05,0.9,0.1,1.1"
            ];
            animation = [
              "windows, 1, 4, overshot, popin 80%"
              "windowsOut, 1, 4, default, popin 90%"
              "border, 1, 2, default"
              "borderangle, 1, 15, overshot"
              "fade, 1, 4, default"
              "workspaces, 0, 0, default"
            ];
          };

          windowrule = [
            # https://wiki.hyprland.org/Configuring/Window-Rules/
            # firefox pip (hacky workaround)
            # https://github.com/hyprwm/Hyprland/issues/2942#issuecomment-1923813933
            "match:title Picture-in-Picture, float on"
            "match:title Picture-in-Picture, move (monitor_w-window_w-${windowLeft}) (monitor_h-${
              toString (pipHeight + gapAndBorderNumeric)
            })"
            "match:title Picture-in-Picture, no_initial_focus on"
            "match:title Picture-in-Picture, pin on"
            "match:title Picture-in-Picture, size 576 ${toString pipHeight}"

            # shimeji desktop pets
            "match:title com-group_finity-mascot-Main, float on"
            "match:title com-group_finity-mascot-Main, no_blur on"
            "match:title com-group_finity-mascot-Main, border_size 0"
            "match:title com-group_finity-mascot-Main, no_focus on"
            "match:title com-group_finity-mascot-Main, no_shadow on"

            # elkowar's wacky widgets
            "match:title eww, float on"

            # zoom windows?
            "match:title ^$, center on"
            "match:title ^$, float on"
            "match:title ^$, no_blur on"
            "match:title ^$, border_size 0"
            "match:title ^$, no_shadow on"
            "match:title ^$, size 25% 100%"

            # improve animation on ueberzugpp windows
            "match:title ueberzugpp.*, animation slide right"

            # zenity
            "match:title zenity, pin on"

            # xdph screenshare picker (hyprland-share-picker)
            "match:title Select what to share, float on"
            "match:title Select what to share, size 500 700"
            "match:title Select what to share, center on"

            # gtk portal file picker (Save As / Open dialogs from Firefox/Chromium)
            "match:class xdg-desktop-portal-gtk, float on"
            "match:class xdg-desktop-portal-gtk, center on"
          ];

          # See https://wiki.hyprland.org/Configuring/Monitors/
          monitor = ",preferred,auto,auto";

          layerrule = [
            # spotlight hosts every picker mode in one layer. Only blur where the
            # panel is (ignore_alpha) — the rest of the layer is a transparent
            # click-catcher — and the panel stays near-opaque (see style.scss) so
            # clipboard-mode image thumbnails don't bloom into the blur.
            "match:namespace spotlight, blur on"
            "match:namespace spotlight, ignore_alpha 0.6"
            # askpass is the same shape — a near-opaque centered panel over a
            # transparent click-catcher — so it takes spotlight's blur as-is.
            "match:namespace askpass, blur on"
            "match:namespace askpass, ignore_alpha 0.6"
            # The notification center is the same shape as spotlight (opaque panel
            # over a transparent click-catcher); the popups are opaque cards over a
            # transparent surface. ignore_alpha keeps the blur on the cards only.
            "match:namespace notification-center, blur on"
            "match:namespace notification-center, ignore_alpha 0.6"
            "match:namespace notification-center-popups, blur on"
            "match:namespace notification-center-popups, ignore_alpha 0.6"
            # Don't let Hyprland animate the popup layer's resize as toasts stack
            # (that's the vertical "stretch"); they fade in via CSS opacity instead.
            "match:namespace notification-center-popups, no_anim on"
            "match:namespace bar, blur on"
            # Threshold (not 0): skip the bar's fully transparent margins so they
            # stay see-through instead of rendering as an opaque blurred band.
            # Must sit below the .bar background alpha so the pill itself blurs.
            "match:namespace bar, ignore_alpha 0.4"
            # The screen-share frame is a solid red edge over an OVERLAY layer:
            # keep it crisp (no blur) and don't animate the strips sliding in.
            "match:namespace screencast-border, blur off"
            "match:namespace screencast-border, no_anim on"
          ];
          # Move/resize windows with mainMod + LMB/RMB and dragging
          bindm = [
            "$mainMod, mouse:272, movewindow"
            "$mainMod SHIFT, mouse:272, resizewindow"
          ];

          binde = [
            "$mainMod, minus, exec,${move-active} shrink"
            "$mainMod SHIFT, minus, exec,${move-active} grow"
          ];

          # https://github.com/sulmone/X11/blob/master/include/X11/XF86keysym.h
          bindel = [
            ", XF86AudioPlay, exec, ${pkgs.playerctl}/bin/playerctl play-pause"
            ", XF86AudioNext, exec, ${pkgs.playerctl}/bin/playerctl next"
            ", XF86AudioPrev, exec, ${pkgs.playerctl}/bin/playerctl previous"
            ", XF86AudioRaiseVolume, exec, ${lib.getExe' pkgs.pulseaudio "pactl"} set-sink-volume @DEFAULT_SINK@ +5%"
            ", XF86AudioLowerVolume, exec, ${lib.getExe' pkgs.pulseaudio "pactl"} set-sink-volume @DEFAULT_SINK@ -5%"
          ];

          bindl = [
            ", XF86AudioMute, exec, ${lib.getExe' pkgs.pulseaudio "pactl"} set-sink-mute @DEFAULT_SINK@ toggle"
            "$mainMod, A, exec, ${virtual-headset-ctl} unmute"
          ];

          # Push-to-talk: trigger on key release
          bindr = [
            "$mainMod, A, exec, ${virtual-headset-ctl} mute"
          ];

          # https://wiki.hypr.land/Configuring/Gestures/
          gesture = [
            "4, horizontal, workspace"
          ];

          # See https://wiki.hyprland.org/Configuring/Keywords/ for more
          "$mainMod" = "SUPER";

          # Example binds, see https://wiki.hyprland.org/Configuring/Binds/ for more
          bind = [
            "$mainMod, Q, killactive,"
            "$mainMod, T, exec, ${config.programs.ghostty.package}/bin/ghostty"
            "$mainMod SHIFT, F, togglefloating,"
            ''$mainMod, F, exec, hyprctl --batch "dispatch togglefloating active; dispatch pin active; dispatch moveactive exact ${windowLeft} ${windowTop}; dispatch resizeactive exact 640 360"''
            "$mainMod ALT,1,exec,${move-active} topLeft"
            "$mainMod ALT,2,exec,${move-active} topRight"
            "$mainMod ALT,3,exec,${move-active} bottomRight"
            "$mainMod ALT,4,exec,${move-active} bottomLeft"
            "$mainMod ALT,5,exec,${move-active} topMiddle"
            "$mainMod ALT,6,exec,${move-active} middleMiddle"
            "$mainMod ALT,7,exec,${move-active} bottomMiddle"
            "$mainMod, P, pin,"
            "$mainMod, Escape, exec, ${pkgs.pkgs-mine.pickers}/bin/spotlight power"
            "$mainMod, B, exec, ${pkgs.pkgs-mine.pickers}/bin/spotlight bluetooth"
            "$mainMod, E, exec, ${pkgs.pkgs-mine.pickers}/bin/spotlight emoji"
            "$mainMod, SPACE, exec, ${pkgs.pkgs-mine.pickers}/bin/spotlight app"
            # "$mainMod, P, pseudo, # dwindle"
            # "$mainMod, T, togglesplit, # dwindle"
            "$mainMod, V, exec, ${pkgs.pkgs-mine.pickers}/bin/spotlight clipboard"
            "$mainMod, S, exec, ${pkgs.hyprshot}/bin/hyprshot -m region -z --clipboard-only"
            "$mainMod SHIFT, S, exec, ${pkgs.hyprshot}/bin/hyprshot -m region -z -o ~/Pictures"
            "$mainMod, N, exec, ${lib.getExe' pkgs.pkgs-mine.notification-center "notifctl"} -t"
            "$mainMod, C, exec, ${config.programs.mpv.package}/bin/mpv av://v4l2:/dev/video1"
            "$mainMod SHIFT, M, exit,"
            "$mainMod, U, exec, ${pkgs.pkgs-mine.uair-toggle-and-notify}/bin/uair-toggle-and-notify"
            # Move focus with mainMod + arrow keys
            "$mainMod, H, movefocus, l"
            "$mainMod, L, movefocus, r"
            "$mainMod, J, movefocus, u"
            "$mainMod, K, movefocus, d"
            # change focus to another window
            "$mainMod, Tab, cyclenext"

            # Switch workspaces with mainMod + [0-9]
            "$mainMod, 1, workspace, 1"
            "$mainMod, 2, workspace, 2"
            "$mainMod, 3, workspace, 3"
            "$mainMod, 4, workspace, 4"
            "$mainMod, 5, workspace, 5"
            "$mainMod, 6, workspace, 6"
            "$mainMod, 7, workspace, 7"
            "$mainMod, 8, workspace, 8"
            "$mainMod, 9, workspace, 9"
            "$mainMod, 0, workspace, 10"

            # Move active window to a workspace with mainMod + SHIFT + [0-9]
            "$mainMod SHIFT, 1, movetoworkspace, 1"
            "$mainMod SHIFT, 2, movetoworkspace, 2"
            "$mainMod SHIFT, 3, movetoworkspace, 3"
            "$mainMod SHIFT, 4, movetoworkspace, 4"
            "$mainMod SHIFT, 5, movetoworkspace, 5"
            "$mainMod SHIFT, 6, movetoworkspace, 6"
            "$mainMod SHIFT, 7, movetoworkspace, 7"
            "$mainMod SHIFT, 8, movetoworkspace, 8"
            "$mainMod SHIFT, 9, movetoworkspace, 9"
            "$mainMod SHIFT, 0, movetoworkspace, 10"

            # Scroll through existing workspaces with mainMod + scroll
            # "$mainMod, mouse_down, workspace, e+1"
            # "$mainMod, mouse_up, workspace, e-1"

            # will switch to a submap called resize
            "ALT,R,submap,resize"
          ];

        };

        extraConfig = # hyprlang
          ''
            # will start a submap called "resize"
            submap=resize
            # sets repeatable binds for resizing the active window
            binde=,right,resizeactive,10 0
            binde=,left,resizeactive,-10 0
            binde=,up,resizeactive,0 -10
            binde=,down,resizeactive,0 10
            binde=,minus,resizeactive,-128 -72
            binde=SHIFT,minus,resizeactive,128 72
            bind=,1,exec,${move-active} topLeft
            bind=,2,exec,${move-active} topRight
            bind=,3,exec,${move-active} bottomRight
            bind=,4,exec,${move-active} bottomLeft
            binde=,l,moveactive,${gaps} 0
            binde=,h,moveactive,-${gaps} 0
            binde=,j,moveactive,0 ${gaps}
            binde=,k,moveactive,0 -${gaps}

            bind=,escape,submap,reset

            # will reset the submap, meaning end the current one and return to the global one
            submap=reset
          '';
      };
  };
}
