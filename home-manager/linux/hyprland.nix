{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.hyprland;
  waybarCfg = config.programs.waybar;
in
{
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

    home.packages = with pkgs; [
      grimblast # screenshot tool
      hyprshade
      # TODO: necessary?
      libnotify
      libva
      libva-utils # hardware video acceleration
      polkit_gnome # just a GUI askpass
      rofi-wayland
      swayidle
      swaylock
      swww
      waypipe
      wl-clipboard
    ];

    home.file.".config/hypr/shaders/red.glsl".text = # glsl
      ''
        precision highp float;
        varying vec2 v_texcoord;
        uniform sampler2D tex;

        void main() {
            vec4 c = texture2D(tex, v_texcoord);
            gl_FragColor = vec4(c.r, 0.0, 0.0, c.a);
        }
      '';

    wayland.windowManager.hyprland =
      let
        inherit (inputs.hyprland.packages.${pkgs.system}) hyprland;
        inherit (cfg) borderSizeNumeric gapsNumeric;
        waybarHeightNumeric = waybarCfg.barHeight;
        gapAndBorderNumeric = gapsNumeric + borderSizeNumeric;
        waybarSpaceNumeric = gapAndBorderNumeric + waybarHeightNumeric - borderSizeNumeric;
        windowTopNumeric = gapAndBorderNumeric + waybarSpaceNumeric;
        windowLeftNumeric = gapsNumeric + borderSizeNumeric;

        gaps = toString gapsNumeric;
        windowLeft = toString windowLeftNumeric;
        windowTop = toString windowTopNumeric;
        windowRight = "100%-w-${windowLeft}";
        move-active = lib.getExe pkgs.pkgs-mine.move-active;
      in
      {
        enable = true;
        package = hyprland;
        systemd.enable = true;
        xwayland.enable = true;
        settings = {
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

            # avg
            "col.inactive_border" = "rgb(631f33)";
            # tetra1, tetra2
            "col.active_border" = "rgb(4bff00) rgb(004bff) 45deg";

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
            workspace_swipe = "on";
            workspace_swipe_distance = 300;
            workspace_swipe_min_speed_to_force = 0;
            workspace_swipe_cancel_ratio = 0;
          };

          misc = {
            animate_manual_resizes = true;
            animate_mouse_windowdragging = true;
            focus_on_activate = true;
          };

          debug = {
            # damage_tracking = false
          };

          # Execute your favorite apps at launch
          exec-once = [
            ''swww init && swww img "~/Downloads/ether.gif"''
            "waybar"
            "swaync"
            "noisetorch -i # load suppressor for input"
            "wl-paste --type text --watch cliphist store"
            "wl-paste --type image --watch cliphist store"
            "firefox"
            "ghostty"
            "${pkgs.networkmanagerapplet}/bin/nm-applet"
            "${pkgs.blueman}/bin/blueman-applet"
            "${pkgs.swayidle}/bin/swayidle timeout 300 '${pkgs.grimblast}/bin/grimblast save screen - | ${pkgs.imagemagick}/bin/magick png:- -scale 10% -blur 0x2.5 -resize 1000% ~/Pictures/out.png && ${pkgs.swaylock}/bin/swaylock -i ~/Pictures/out.png' timeout 600 'hyprctl dispatch dpms off' resume 'hyprctl dispatch dpms on'"
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

          windowrulev2 = [
            # https://wiki.hyprland.org/Configuring/Window-Rules/
            # firefox pip (hacky workaround)
            # https://github.com/hyprwm/Hyprland/issues/2942#issuecomment-1923813933
            "float, title:^(Picture-in-Picture)$"
            "move ${windowRight} ${windowTop}, title:(Picture-in-Picture)"
            "noinitialfocus, title:^(Picture-in-Picture)$"
            "pin, title:^(Picture-in-Picture)$"
            "size 640 360, title:(Picture-in-Picture)"

            # shimeji desktop pets
            "float, title:^(com-group_finity-mascot-Main)$"
            "noblur, title:^(com-group_finity-mascot-Main)$"
            "noborder, title:^(com-group_finity-mascot-Main)$"
            "nofocus, title:^(com-group_finity-mascot-Main)$"
            "noshadow, title:^(com-group_finity-mascot-Main)$"

            # elkowar's wacky widgets
            "float, title:^(eww)$"

            # zoom windows?
            "center, title:^()$"
            "float, title:^()$"
            "noblur, title:^()$"
            "noborder, title:^()$"
            "noshadow, title:^()$"
            "size 25% 100%, title:^()$"

            # sway notifications
            "move ${windowRight} ${windowTop}, title:^(swaync)$"
            "noinitialfocus, title:^(swaync)$"
            "pin, title:^(swaync)$"

            # improve animation on ueberzugpp windows
            "animation slide right, title:^(ueberzugpp.*)"

            # zenity
            "pin, title:^(zenity)$"
          ];

          # See https://wiki.hyprland.org/Configuring/Monitors/
          monitor = ",preferred,auto,auto";

          layerrule = [
            "blur,notifications"
            "blur,rofi"
            "blur,swaync"
            "blur,swaynotificationcenter"
            "blur,waybar"
            "ignorezero,rofi"
            "ignorezero,waybar"
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

          # TODO: add more from:
          # https://github.com/sulmone/X11/blob/master/include/X11/XF86keysym.h
          bindel = [
            ", XF86AudioPlay, exec, playerctl play-pause"
            ", XF86AudioNext, exec, playerctl next"
            ", XF86AudioPrev, exec, playerctl previous"
            ", XF86AudioRaiseVolume, exec, pactl set-sink-volume @DEFAULT_SINK@ +5%"
            ", XF86AudioLowerVolume, exec, pactl set-sink-volume @DEFAULT_SINK@ -5%"
            # ", XF86AudioRaiseVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"
            # ", XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"
          ];

          bindl = [
            ", XF86AudioMute, exec, pactl set-sink-mute @DEFAULT_SINK@ toggle"
            # ", XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
          ];

          # See https://wiki.hyprland.org/Configuring/Keywords/ for more
          "$mainMod" = "SUPER";

          # Example binds, see https://wiki.hyprland.org/Configuring/Binds/ for more
          bind = [
            "$mainMod, Q, killactive,"
            "$mainMod, T, exec, ghostty"
            "$mainMod SHIFT, F, togglefloating,"
            ''$mainMod, F, exec, hyprctl --batch "dispatch togglefloating active; dispatch pin active; dispatch moveactive exact ${windowLeft} ${windowTop}; dispatch resizeactive exact 640 360"''
            "$mainMod ALT,1,exec,${move-active} topLeft"
            "$mainMod ALT,2,exec,${move-active} topRight"
            "$mainMod ALT,3,exec,${move-active} bottomRight"
            "$mainMod ALT,4,exec,${move-active} bottomLeft"
            "$mainMod, P, pin,"
            # "$mainMod, E, exec, dolphin"
            "$mainMod, SPACE, exec, rofi -show drun -show-icons"
            # "$mainMod, P, pseudo, # dwindle"
            # "$mainMod, T, togglesplit, # dwindle"
            "$mainMod, V, exec, cliphist list | rofi -dmenu | cliphist decode | wl-copy"
            "$mainMod SHIFT, V, exec, rofi-rbw"
            "$mainMod, S, exec, grimblast copy area"
            "$mainMod SHIFT, S, exec, grimblast save area"
            "$mainMod, N, exec, swaync-client -t"
            "$mainMod, C, exec, mpv av://v4l2:/dev/video1"
            # "$mainMod SHIFT, F6, exec, playerctl previous"
            # "$mainMod SHIFT, F7, exec, playerctl play-pause"
            # "$mainMod, F7, exec, playerctl play-pause"
            # ", F7, exec, playerctl play-pause"
            # "$mainMod SHIFT, F8, exec, playerctl next"

            # "$mainMod, F6, exec, pactl set-sink-volume @DEFAULT_SINK@ -5%"
            # "$mainMod, F7, exec, pactl set-sink-mute @DEFAULT_SINK@ toggle"
            # "$mainMod, F8, exec, pactl set-sink-volume @DEFAULT_SINK@ +5%"
            "$mainMod SHIFT, M, exit,"
            # TODO: make real program
            "$mainMod, U, exec, uair-toggle-and-notify"
            # Move focus with mainMod + arrow keys
            "$mainMod, H, movefocus, l"
            "$mainMod, L, movefocus, r"
            "$mainMod, J, movefocus, u"
            "$mainMod, K, movefocus, d"
            "$mainMod, Tab, cyclenext,           # change focus to another window"

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

        # TODO: make proper options
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
