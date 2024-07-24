{ inputs, pkgs, ... }:
{
  home.sessionVariables = {
    NVD_BACKEND = "direct"; # github:elFarto
    MOZ_DISABLE_RDD_SANDBOX = "1";
    NIXOS_OZONE_WL = "1";
    LIBVA_DRIVER_NAME = "nvidia";
    GBM_BACKEND = "nvidia-drm";
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
    WLR_RENDERER_ALLOW_SOFTWARE = "1";
  };
  home.packages = with pkgs; [
    cava # audio visualizer
    grimblast # screenshot tool
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
  wayland.windowManager.hyprland =
    let
      hyprland = inputs.hyprland.packages.${pkgs.system}.hyprland;
    in
    {
      enable = true;
      package = hyprland;
      systemd.enable = true;
      xwayland.enable = true;
      # TODO: make proper options
      extraConfig = # hyprlang
        ''
          # See https://wiki.hyprland.org/Configuring/Monitors/
          monitor=,preferred,auto,auto


          # See https://wiki.hyprland.org/Configuring/Keywords/ for more

          # Execute your favorite apps at launch
          exec-once = swww init && swww img "~/Downloads/ether.gif"
          exec-once = waybar 
          exec-once = swaync
          exec-once = noisetorch -i # load suppressor for input
          exec-once = wl-paste --type text --watch cliphist store
          exec-once = wl-paste --type image --watch cliphist store
          exec-once = firefox
          exec-once = kitty
          exec-once = neovide
          # exec-once = swayidle timeout 300 'grimblast save screen - | convert png:- -scale 10% -blur 0x2.5 -resize 1000% ~/Pictures/out.png && swaylock -i ~/Pictures/out.png' timeout 600 'hyprctl dispatch dpms off && openrgb -p off' resume 'hyprctl dispatch dpms on && openrgb -p pink'

          # Source a file (multi-file configs)
          # source = ~/.config/hypr/myColors.conf

          # Some default env vars.
          env = XCURSOR_SIZE,24
          # I guess this is how you can set better nvidia variables
          env = LIBVA_DRIVER_NAME,nvidia
          env = XDG_SESSION_TYPE,wayland
          env = GBM_BACKEND,nvidia-drm
          env = __GLX_VENDOR_LIBRARY_NAME,nvidia
          env = WLR_NO_HARDWARE_CURSORS,1
          env = WLR_RENDERER_ALLOW_SOFTWARE,1
          # There is lots of weird edge cases listed here:
          # https://wiki.hyprland.org/Nvidia/#how-to-get-hyprland-to-possibly-work-on-nvidia

          # For all categories, see https://wiki.hyprland.org/Configuring/Variables/
          input {
              kb_layout = us
              kb_variant =
              kb_model =
              kb_rules =
              # probably don't do this
              # kb_options = caps:swapescape
              follow_mouse = 1

              touchpad {
                  natural_scroll = yes
                  scroll_factor = 0.8
              }
              sensitivity = 0.0 # -1.0 - 1.0, 0 means no modification.
          }

          # I think turning this option on slows down my computer
          #  I think one of thesse is the bluetooth version
          # device:by-tech-air75 {
          #     repeat_rate=100
          #     repeat_delay=300
          #     middle_button_emulation=0
          # }
          # device:by-tech-air75-1 {
          #     repeat_rate=100
          #     repeat_delay=300
          #     middle_button_emulation=0
          # }

          general {
              # See https://wiki.hyprland.org/Configuring/Variables/ for more
              sensitivity = 2.2

              gaps_in = 5
              gaps_out = 10
              border_size = 4

              # avg
              col.inactive_border = rgb(631f33)
              # tetra1, tetra2
              col.active_border = rgb(4bff00) rgb(004bff) 45deg

              layout = dwindle
          }

          decoration {
              # See https://wiki.hyprland.org/Configuring/Variables/ for more
              # make it match border-width for ultimate roundness
              rounding = 4

              blur {
                  enabled = true
                  size = 8
                  passes = 2
              }

              drop_shadow = yes
              shadow_range = 4
              shadow_render_power = 3
              col.shadow = rgba(1a1a1aee)
          }

          animations {
              enabled = yes

              # Some default animations, see https://wiki.hyprland.org/Configuring/Animations/ for more

              bezier = myBezier, 0.05, 0.9, 0.1, 1.05
              bezier=overshot,0.05,0.9,0.1,1.1

              animation = windows, 1, 4, overshot, popin 80%
              animation = windowsOut, 1, 4, default, popin 90%
              animation = border, 1, 2, default
              animation = borderangle, 1, 15, overshot
              animation = fade, 1, 4, default
              animation = workspaces, 0, 0, default
          }

          dwindle {
              # See https://wiki.hyprland.org/Configuring/Dwindle-Layout/ for more
              pseudotile = yes # master switch for pseudotiling. Enabling is bound to mainMod + P in the keybinds section below
              preserve_split = yes # you probably want this
          }

          master {
              # See https://wiki.hyprland.org/Configuring/Master-Layout/ for more
              new_status = "master" # "slave"
          }

          gestures {
              # See https://wiki.hyprland.org/Configuring/Variables/ for more
              workspace_swipe = on
              workspace_swipe_distance = 300
              workspace_swipe_min_speed_to_force = 0
              workspace_swipe_cancel_ratio = 0
          }

          # Example per-device config
          # See https://wiki.hyprland.org/Configuring/Keywords/#executing for more
          # device:epic-mouse-v1 {
          #     sensitivity = -0.5
          # }

          misc {
            animate_manual_resizes = true
            animate_mouse_windowdragging = true
            focus_on_activate = true
          }


          debug {
            # damage_tracking = false
          }

          # https://wiki.hyprland.org/Configuring/Window-Rules/
          # firefox pip (hacky workaround)
          # https://github.com/hyprwm/Hyprland/issues/2942#issuecomment-1923813933
          windowrulev2 = size 640 360, title:(Picture-in-Picture)
          windowrulev2 = pin, title:^(Picture-in-Picture)$
          windowrulev2 = move 1906 14, title:(Picture-in-Picture)
          windowrulev2 = float, title:^(Picture-in-Picture)$
          # windowrulev2 = size 640 360, title:(Firefox)
          # windowrulev2 = pin, title:^(Firefox)$
          # windowrulev2 = move 1906 14, title:(Firefox)

          # shimeji desktop pets
          windowrule=float, com-group_finity-mascot-Main
          windowrule=noblur, com-group_finity-mascot-Main
          windowrule=nofocus, com-group_finity-mascot-Main
          windowrule=noshadow, com-group_finity-mascot-Main
          windowrule=noborder, com-group_finity-mascot-Main

          # elkowar's wacky widgets
          windowrule=float, ^(eww)$

          # zoom windows?
          windowrule=float, title:^()$
          windowrule=size 25% 100%, title:^()$
          windowrule=center, title:^()$
          windowrule=noblur, title:^()$
          windowrule=noborder, title:^()$
          windowrule=noshadow, title:^()$


          blurls=notifications
          blurls=swaync
          blurls=swaynotificationcenter
          blurls=waybar
          layerrule=ignorezero,waybar
          blurls=rofi
          layerrule=ignorezero,rofi

          # See https://wiki.hyprland.org/Configuring/Keywords/ for more
          $mainMod = SUPER

          # Example binds, see https://wiki.hyprland.org/Configuring/Binds/ for more
          bind = $mainMod, Q, killactive,
          bind = $mainMod, T, exec, alacritty
          bind = $mainMod SHIFT, F, togglefloating,
          bind = $mainMod, F, exec, hyprctl --batch "dispatch togglefloating active; dispatch pin active; dispatch moveactive exact 14 14; dispatch resizeactive exact 640 360"
          bind = $mainMod, minus, resizeactive,-128 -72
          bind = $mainMod SHIFT, minus, resizeactive,128 72
          bind = $mainMod ALT,1,moveactive,exact 14 14
          bind = $mainMod ALT,2,moveactive,exact 1906 14
          bind = $mainMod ALT,3,moveactive,exact 1906 1024
          bind = $mainMod ALT,4,moveactive,exact 14 1024
          # hyprctl --batch "dispatch togglefloating active; dispatch pin active; dispatch moveactive exact 14 14; dispatch resizeactive exact 384 216"
          bind = $mainMod, P, pin,
          # bind = $mainMod, E, exec, dolphin
          bind = $mainMod, SPACE, exec, rofi -show drun -show-icons
          # bind = $mainMod, P, pseudo, # dwindle
          # bind = $mainMod, T, togglesplit, # dwindle
          bind = $mainMod, V, exec, cliphist list | rofi -dmenu | cliphist decode | wl-copy
          bind = $mainMod SHIFT, V, exec, rofi-rbw
          bind = $mainMod, S, exec, grimblast copy area
          bind = $mainMod SHIFT, S, exec, grimblast save area
          bind = $mainMod, N, exec, swaync-client -t
          bind = $mainMod, C, exec, mpv av://v4l2:/dev/video1
          # bind = $mainMod SHIFT, F6, exec, playerctl previous
          # bind = $mainMod SHIFT, F7, exec, playerctl play-pause
          # bind = $mainMod, F7, exec, playerctl play-pause
          # bind = , F7, exec, playerctl play-pause
          # bind = $mainMod SHIFT, F8, exec, playerctl next
          bindel=, XF86AudioPlay, exec, playerctl play-pause
          bindel=, XF86AudioNext, exec, playerctl next
          bindel=, XF86AudioPrev, exec, playerctl previous

          # TODO: add more from:
          # https://github.com/sulmone/X11/blob/master/include/X11/XF86keysym.h

          # bind = $mainMod, F6, exec, pactl set-sink-volume @DEFAULT_SINK@ -5%
          # bind = $mainMod, F7, exec, pactl set-sink-mute @DEFAULT_SINK@ toggle
          # bind = $mainMod, F8, exec, pactl set-sink-volume @DEFAULT_SINK@ +5%
          bindel=, XF86AudioRaiseVolume, exec, pactl set-sink-volume @DEFAULT_SINK@ +5%
          bindel=, XF86AudioLowerVolume, exec, pactl set-sink-volume @DEFAULT_SINK@ -5%
          bindl=, XF86AudioMute, exec, pactl set-sink-mute @DEFAULT_SINK@ toggle
          # bindel=, XF86AudioRaiseVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+
          # bindel=, XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
          # bindl=, XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
          bind = $mainMod SHIFT, M, exit,
          # TODO: make real program
          bind = $mainMod, U, exec, uair-toggle-and-notify
          # Move focus with mainMod + arrow keys
          bind = $mainMod, H, movefocus, l
          bind = $mainMod, L, movefocus, r
          bind = $mainMod, J, movefocus, u
          bind = $mainMod, K, movefocus, d

          # Switch workspaces with mainMod + [0-9]
          bind = $mainMod, 1, workspace, 1
          bind = $mainMod, 2, workspace, 2
          bind = $mainMod, 3, workspace, 3
          bind = $mainMod, 4, workspace, 4
          bind = $mainMod, 5, workspace, 5
          bind = $mainMod, 6, workspace, 6
          bind = $mainMod, 7, workspace, 7
          bind = $mainMod, 8, workspace, 8
          bind = $mainMod, 9, workspace, 9
          bind = $mainMod, 0, workspace, 10

          # Move active window to a workspace with mainMod + SHIFT + [0-9]
          bind = $mainMod SHIFT, 1, movetoworkspace, 1
          bind = $mainMod SHIFT, 2, movetoworkspace, 2
          bind = $mainMod SHIFT, 3, movetoworkspace, 3
          bind = $mainMod SHIFT, 4, movetoworkspace, 4
          bind = $mainMod SHIFT, 5, movetoworkspace, 5
          bind = $mainMod SHIFT, 6, movetoworkspace, 6
          bind = $mainMod SHIFT, 7, movetoworkspace, 7
          bind = $mainMod SHIFT, 8, movetoworkspace, 8
          bind = $mainMod SHIFT, 9, movetoworkspace, 9
          bind = $mainMod SHIFT, 0, movetoworkspace, 10

          # Scroll through existing workspaces with mainMod + scroll
          # bind = $mainMod, mouse_down, workspace, e+1
          # bind = $mainMod, mouse_up, workspace, e-1

          # Move/resize windows with mainMod + LMB/RMB and dragging
          bindm = $mainMod, mouse:272, movewindow
          bindm = SHIFT, mouse:273, resizewindow

          # will switch to a submap called resize
          bind=ALT,R,submap,resize
          # will start a submap called "resize"
          submap=resize
          # sets repeatable binds for resizing the active window
          binde=,right,resizeactive,10 0
          binde=,left,resizeactive,-10 0
          binde=,up,resizeactive,0 -10
          binde=,down,resizeactive,0 10
          binde=,minus,resizeactive,-128 -72
          binde=SHIFT,minus,resizeactive,128 72
          bind=,1,moveactive,exact 14 14
          bind=,2,moveactive,exact 1906 14
          bind=,3,moveactive,exact 1906 1024
          bind=,4,moveactive,exact 14 1024
          binde=,l,moveactive,14 0
          binde=,h,moveactive,-14 0
          binde=,j,moveactive,0 14
          binde=,k,moveactive,0 -14

          bind=,escape,submap,reset

          # will reset the submap, meaning end the current one and return to the global one
          submap=reset
        '';
    };
}
