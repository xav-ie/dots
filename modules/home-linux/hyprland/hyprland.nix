{
  flake.modules.homeManager.linux =
    {
      config,
      inputs,
      lib,
      osConfig,
      pkgs,
      fonts,
      hyprlock-weather,
      ...
    }:
    let
      cfg = config.programs.hyprland;
      barCfg = config.programs.ags-bar;
      # Same `sans` (Inter) the pickers/bar use, so hyprlock tracks the system font.
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
          # Route Mesa GL through zink (Vulkan → NVIDIA) instead of llvmpipe. On
          # wlroots/NVIDIA every Wayland client's EGL display comes from Mesa
          # (NVIDIA's vendor doesn't offer the Wayland platform at all), and Mesa
          # has no native driver for this GPU — so without this every GL app
          # software-renders on the CPU. Measured on ghostty: 146% CPU on
          # llvmpipe vs a few percent on zink.
          MESA_LOADER_DRIVER_OVERRIDE = "zink";
          MOZ_DISABLE_RDD_SANDBOX = "1";
          NIXOS_OZONE_WL = "1";
          # direct: elFarto exports the decoded NVDEC surface as a block-linear
          # dma-buf that zink imports zero-copy. This needs the zink import fix in
          # mesaMain (zink-nvidia-import-no-export.patch): without it zink requested
          # export handles on the imported dma-buf, which flips NVIDIA's tiling kind
          # so the surface reads back as zero (solid green video). With the patch,
          # HW video decode works on native Wayland with correct colors.
          NVD_BACKEND = "direct"; # github:elFarto
          WLR_NO_HARDWARE_CURSORS = "1";
          WLR_RENDERER_ALLOW_SOFTWARE = "1";
          XCURSOR_SIZE = "24";
          XDG_SESSION_TYPE = "wayland";
          __GLX_VENDOR_LIBRARY_NAME = "nvidia";
        };

        # Systemd user services never source ~/.profile, so hypridle — and the
        # hyprlock it spawns — otherwise runs without the GL vars above: Mesa
        # finds no driver for the NVIDIA pci id and gbm can't allocate, so the
        # lock screen renders nothing at all.
        systemd.user.sessionVariables = {
          inherit (config.home.sessionVariables) GBM_BACKEND MESA_LOADER_DRIVER_OVERRIDE;
        };

        home.pointerCursor = {
          enable = true;
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
          satty # screenshot annotator
          waypipe
          wl-clipboard
        ];

        programs = {
          hyprlock = {
            enable = true;
            package = pkgs.hyprlock.overrideAttrs (old: {
              patches = (old.patches or [ ]) ++ [ ./hyprlock-zink-flush.patch ];
            });
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

              # Baked by hyprlock-potd (picture of the day + blurred cards, graphs and agenda bars
              # behind the labels below); reloaded while locked so an hourly re-bake shows up.
              background = {
                monitor = "";
                path = "${config.xdg.cacheHome}/hyprlock/potd-lock.jpg";
                reload_time = 300;
                color = "rgb(26, 23, 38)";
              };

              input-field = {
                # monitor =
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

                # size and position must match the blur patch hyprlock-potd bakes behind it
                size = "512, 72";
                position = "-50, 110";
                halign = "right";
                valign = "bottom";
              };

              # Two cards (Today | Tomorrow) top left; hyprlock-potd bakes their backgrounds at these
              # positions (700px text columns at x=80 and x=890, y=80), so keep the two in step.
              label =
                let
                  fg = "rgb(242, 238, 251)"; # fg (#f2eefb)
                  mono = "CaskaydiaCove Nerd Font Mono";
                  # tight, dark shadow: a small size spread over 4 passes (hyprlock's blur doubles
                  # per pass; big sizes with few passes break into a grid)
                  shadow = {
                    shadow_passes = 4;
                    shadow_size = 6;
                    shadow_color = "rgb(0, 0, 0)";
                    shadow_boost = 4.2;
                  };
                  card =
                    day:
                    {
                      monitor = "";
                      text = "cmd[update:900000] ${lib.getExe hyprlock-weather} ${toString day}";
                      color = fg;
                      font_size = 38;
                      font_family = mono;
                      text_align = "left";
                      position = "${toString (80 + day * 810)}, -80";
                      halign = "left";
                      valign = "top";
                    }
                    // shadow
                    // {
                      shadow_boost = 5.2;
                    };
                  # high/low flush right on the weather row (the script pads it to that baseline)
                  hilo =
                    day:
                    card day
                    // {
                      text = "cmd[update:900000] ${lib.getExe hyprlock-weather} ${toString day} --hilo";
                      text_align = "right";
                      position = "-${toString (1780 - day * 810)}, -80";
                      halign = "right";
                    };
                  date =
                    day: fmt:
                    {
                      monitor = "";
                      text = ''cmd[update:60000] date ${fmt}+"%a, %-d %b"'';
                      color = fg;
                      font_size = 30;
                      font_family = "$font";
                      position = "-${toString (1780 - day * 810)}, -115";
                      halign = "right";
                      valign = "top";
                    }
                    // shadow;
                in
                [
                  # TIME, in the Today card's header slot
                  (
                    {
                      monitor = "";
                      text = ''cmd[update:1000] date +"%-I:%M %p"'';
                      color = fg;
                      font_size = 57;
                      font_family = "$font";
                      position = "80, -80";
                      halign = "left";
                      valign = "top";
                    }
                    // shadow
                    // {
                      shadow_boost = 5.3;
                    }
                  )
                  (date 0 "")
                  (date 1 "-d tomorrow ")
                  (card 0)
                  (card 1)
                  (hilo 0)
                  (hilo 1)
                  # picture-of-the-day caption
                  (
                    {
                      monitor = "";
                      text = "cmd[update:3600000] cat ${config.xdg.cacheHome}/hyprlock/potd.txt";
                      color = fg;
                      font_size = 14;
                      font_family = "$font";
                      text_align = "right";
                      position = "-50, 40";
                      halign = "right";
                      valign = "bottom";
                    }
                    // shadow
                  )
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
                after_sleep_cmd = "hyprctl dispatch 'hl.dsp.dpms({ action = \"on\" })'";
                # pidof guard: a second hyprlock racing the first for the GPU fails
                # zink's vkCreateDevice and falls back to llvmpipe (~2 cores, fans).
                lock_cmd = "${pkgs.procps}/bin/pidof hyprlock || ${config.programs.hyprlock.package}/bin/hyprlock --grace 10 || true";
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
                  on-timeout = "hyprctl dispatch 'hl.dsp.dpms({ action = \"off\" })'";
                  on-resume = "hyprctl dispatch 'hl.dsp.dpms({ action = \"on\" })'";
                }
              ]
              ++ lib.optionals osConfig.services.power-save.enable [
                {
                  # Demand-driven power save: after 30 min idle, drop the seat
                  # stamp so the power-arbiter is free to fall to idle; on
                  # return, clear it and wake to full speed instantly.
                  #
                  # Both hooks are single-token wrapper scripts: their logic
                  # lives behind a shebang, so they're correct regardless of how
                  # hypridle execs listener commands (and trivially extensible).
                  timeout = 1800;
                  on-timeout = "${pkgs.writeShellScript "power-seat-idle" ''
                    ${pkgs.coreutils}/bin/touch /run/power-arbiter/seat-idle
                  ''}";
                  on-resume = "${pkgs.writeShellScript "power-seat-resume" ''
                    ${pkgs.coreutils}/bin/rm -f /run/power-arbiter/seat-idle
                    ${pkgs.systemd}/bin/systemctl start power-save-exit.service
                  ''}";
                }
              ];
            };
          };

        };

        # hypridle self-heal: an unmatched idle-uninhibit underflows hypridle's
        # lock counter ("inhibit locks < 0", an upstream bug) and freezes its
        # event loop — on-resume stops firing and stale state (e.g. our
        # seat-idle stamp) never clears. Follow its journal and restart it the
        # instant that line appears, so it can never stay wedged.
        systemd.user.services.hypridle-watchdog = {
          Unit = {
            Description = "Restart hypridle when its inhibit-lock counter underflows (upstream bug)";
            After = [ "hypridle.service" ];
            PartOf = [ "graphical-session.target" ];
          };
          Service = {
            Type = "simple";
            Restart = "always";
            RestartSec = 5;
            ExecStart = "${pkgs.writeShellScript "hypridle-watchdog" # sh
              ''
                ${pkgs.systemd}/bin/journalctl --user -u hypridle -f -n 0 -o cat |
                  while read -r line; do
                    case "$line" in
                      *"inhibit locks < 0"*)
                        now=$(${pkgs.coreutils}/bin/date +%s)
                        last=$(${pkgs.coreutils}/bin/cat "$XDG_RUNTIME_DIR/hypridle-watchdog.stamp" 2>/dev/null || echo 0)
                        # debounce so a restart can't thrash
                        if [ $((now - last)) -ge 30 ]; then
                          echo "$now" > "$XDG_RUNTIME_DIR/hypridle-watchdog.stamp"
                          echo "hypridle-watchdog: inhibit-lock underflow -> restarting hypridle"
                          ${pkgs.systemd}/bin/systemctl --user restart hypridle
                        fi
                        ;;
                    esac
                  done
              ''
            }";
          };
          Install.WantedBy = [ "graphical-session.target" ];
        };

        wayland.windowManager.hyprland =
          let
            inherit (inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}) hyprland;
            inherit (cfg) borderSizeNumeric gapsNumeric;
            inherit (lib.generators) mkLuaInline;
            toLua = lib.generators.toLua { };
            barHeightNumeric = barCfg.barHeight;
            gapAndBorderNumeric = gapsNumeric + borderSizeNumeric;
            barSpaceNumeric = gapAndBorderNumeric + barHeightNumeric - borderSizeNumeric;
            windowTopNumeric = gapAndBorderNumeric + barSpaceNumeric;
            windowLeftNumeric = gapsNumeric + borderSizeNumeric;

            pipHeight = 324;
            move-active = "${pkgs.pkgs-mine.move-active}/bin/move-active";
            spotlight = "${pkgs.pkgs-mine.pickers}/bin/spotlight";
            pactl = lib.getExe' pkgs.pulseaudio "pactl";
            virtual-headset-ctl = "${
              inputs.virtual-headset.packages.${pkgs.stdenv.hostPlatform.system}.virtual-headset-ctl
            }/bin/virtual-headset-ctl";

            mod = "SUPER";
            dsp = action: mkLuaInline "hl.dsp.${action}";
            exec = command: mkLuaInline "hl.dsp.exec_cmd(${toLua command})";
            # hl.bind(keys, dispatcher[, opts])
            bind = keys: action: {
              _args = [
                keys
                action
              ];
            };
            bindWith = opts: keys: action: {
              _args = [
                keys
                action
                opts
              ];
            };
            locked = bindWith { locked = true; };
            release = bindWith { release = true; };
            repeating = bindWith { repeating = true; };
            repeatingLocked = bindWith {
              locked = true;
              repeating = true;
            };
            matchTitle = title: rule: { match.title = title; } // rule;
            # Layer surfaces that draw a near-opaque panel over a transparent
            # click-catcher: blur only where the panel is.
            frosted = namespace: alpha: {
              match.namespace = namespace;
              blur = true;
              ignore_alpha = alpha;
            };
          in
          {
            enable = true;
            package = hyprland;
            configType = "lua";
            systemd.enable = true;
            xwayland.enable = true;
            settings = {
              env = map (args: { _args = args; }) [
                [
                  "XCURSOR_THEME"
                  config.home.pointerCursor.name
                ]
                [
                  "XCURSOR_SIZE"
                  (toString config.home.pointerCursor.size)
                ]
                [
                  "HYPRCURSOR_THEME"
                  config.home.pointerCursor.name
                ]
                [
                  "HYPRCURSOR_SIZE"
                  (toString config.home.pointerCursor.size)
                ]
              ];

              # For all options, see https://wiki.hypr.land/configuring/core/config-options/
              config = {
                input = {
                  kb_layout = "us";
                  follow_mouse = 1;
                  touchpad = {
                    natural_scroll = true;
                    scroll_factor = 0.8;
                  };
                  # -1.0 - 1.0, 0 means no modification.
                  sensitivity = 0.0;
                };

                general = {
                  gaps_in = gapsNumeric / 2;
                  gaps_out = gapsNumeric;
                  border_size = borderSizeNumeric;
                  # darker/saturated take on packages/pickers accent ($accent #bb9af7)
                  col = {
                    inactive_border = "rgb(3a2e5e)";
                    active_border = "rgb(7c5cba)";
                  };
                  layout = "dwindle";
                };

                decoration = {
                  # make it match border-width for ultimate roundness
                  rounding = 4;
                  blur = {
                    enabled = true;
                    size = 8;
                    passes = 3;
                  };
                  shadow.enabled = false;
                };

                dwindle.preserve_split = true;
                master.new_status = "master";

                gestures = {
                  workspace_swipe_distance = 300;
                  workspace_swipe_min_speed_to_force = 0;
                  workspace_swipe_cancel_ratio = 0;
                };

                misc = {
                  allow_session_lock_restore = true;
                  animate_manual_resizes = true;
                  animate_mouse_windowdragging = true;
                  focus_on_activate = true;
                };

                cursor.hide_on_key_press = true;
                animations.enabled = true;
              };

              # See https://wiki.hypr.land/configuring/core/monitors/
              monitor = {
                output = "";
                mode = "preferred";
                position = "auto";
                scale = "auto";
              };

              # See https://wiki.hypr.land/configuring/core/animations/
              curve = map (args: { _args = args; }) [
                [
                  "myBezier"
                  {
                    type = "bezier";
                    points = [
                      [
                        5.0e-2
                        0.9
                      ]
                      [
                        0.1
                        1.05
                      ]
                    ];
                  }
                ]
                [
                  "overshot"
                  {
                    type = "bezier";
                    points = [
                      [
                        5.0e-2
                        0.9
                      ]
                      [
                        0.1
                        1.1
                      ]
                    ];
                  }
                ]
              ];
              animation = [
                {
                  leaf = "windows";
                  enabled = true;
                  speed = 4;
                  bezier = "overshot";
                  style = "popin 80%";
                }
                {
                  leaf = "windowsOut";
                  enabled = true;
                  speed = 4;
                  bezier = "default";
                  style = "popin 90%";
                }
                {
                  leaf = "border";
                  enabled = true;
                  speed = 2;
                  bezier = "default";
                }
                {
                  leaf = "borderangle";
                  enabled = true;
                  speed = 15;
                  bezier = "overshot";
                }
                {
                  leaf = "fade";
                  enabled = true;
                  speed = 4;
                  bezier = "default";
                }
                {
                  leaf = "workspaces";
                  enabled = false;
                }
              ];

              # See https://wiki.hypr.land/configuring/core/rules/
              window_rule = [
                # firefox pip (hacky workaround)
                # https://github.com/hyprwm/Hyprland/issues/2942#issuecomment-1923813933
                (matchTitle "Picture-in-Picture" {
                  float = true;
                  move = "(monitor_w-window_w-${toString windowLeftNumeric}) (monitor_h-${
                    toString (pipHeight + gapAndBorderNumeric)
                  })";
                  no_initial_focus = true;
                  pin = true;
                  size = "576 ${toString pipHeight}";
                })
                # shimeji desktop pets
                (matchTitle "com-group_finity-mascot-Main" {
                  float = true;
                  no_blur = true;
                  border_size = 0;
                  no_focus = true;
                  no_shadow = true;
                })
                # elkowar's wacky widgets
                (matchTitle "eww" { float = true; })
                # zoom windows?
                (matchTitle "^$" {
                  center = true;
                  float = true;
                  no_blur = true;
                  border_size = 0;
                  no_shadow = true;
                  size = "25% 100%";
                })
                # improve animation on ueberzugpp windows
                (matchTitle "ueberzugpp.*" { animation = "slide right"; })
                (matchTitle "zenity" { pin = true; })
                # xdph screenshare picker (hyprland-share-picker)
                (matchTitle "Select what to share" {
                  float = true;
                  size = "500 700";
                  center = true;
                })
                # gtk portal file picker (Save As / Open dialogs from Firefox/Chromium)
                {
                  match.class = "xdg-desktop-portal-gtk";
                  float = true;
                  center = true;
                }
              ];

              layer_rule = [
                # spotlight hosts every picker mode in one layer; the panel stays
                # near-opaque (see style.scss) so clipboard-mode image thumbnails
                # don't bloom into the blur.
                (frosted "spotlight" 0.6)
                (frosted "askpass" 0.6)
                (frosted "notification-center" 0.6)
                (frosted "notification-center-popups" 0.6)
                # Don't let Hyprland animate the popup layer's resize as toasts stack
                # (that's the vertical "stretch"); they fade in via CSS opacity instead.
                {
                  match.namespace = "notification-center-popups";
                  no_anim = true;
                }
                (frosted "osd" 0.6)
                # Threshold (not 0): skip the bar's fully transparent margins so they
                # stay see-through instead of rendering as an opaque blurred band.
                # Must sit below the .bar background alpha so the pill itself blurs.
                (frosted "bar" 0.4)
                # The screen-share frame is a solid red edge over an OVERLAY layer:
                # keep it crisp (no blur) and don't animate the strips sliding in.
                {
                  match.namespace = "screencast-border";
                  blur = false;
                  no_anim = true;
                }
              ];

              # https://wiki.hypr.land/configuring/core/gestures/
              gesture = {
                fingers = 4;
                direction = "horizontal";
                action = "workspace";
              };

              # Execute your favorite apps at launch. hyprpaper is started via its
              # own home-manager systemd user service.
              on = {
                _args = [
                  "hyprland.start"
                  (mkLuaInline ''
                    function()
                      hl.exec_cmd(${toLua "${lib.getExe' pkgs.wl-clipboard "wl-paste"} --type text --watch cliphist store"})
                      hl.exec_cmd(${toLua "${lib.getExe' pkgs.wl-clipboard "wl-paste"} --type image --watch cliphist store"})
                      -- Pre-warm the spotlight launcher so the picker keybinds open
                      -- instantly (it stays resident and just switches/toggles its mode).
                      hl.exec_cmd(${toLua "${spotlight} --daemon"})
                      hl.exec_cmd(${toLua "${config.programs.firefox.package}/bin/firefox"}, { workspace = "2 silent" })
                      hl.exec_cmd(${toLua "${config.programs.ghostty.package}/bin/ghostty"}, { workspace = "1 silent" })
                    end'')
                ];
              };

              # See https://wiki.hypr.land/configuring/core/binds/
              bind = [
                (bind "${mod} + Q" (dsp "window.close()"))
                (bind "${mod} + T" (exec "${config.programs.ghostty.package}/bin/ghostty"))
                (bind "${mod} + SHIFT + F" (dsp ''window.float({ action = "toggle" })''))
                (bind "${mod} + F" (mkLuaInline ''
                  function()
                    hl.dispatch(hl.dsp.window.float({ action = "toggle" }))
                    hl.dispatch(hl.dsp.window.pin())
                    hl.dispatch(hl.dsp.window.move({ x = ${toString windowLeftNumeric}, y = ${toString windowTopNumeric} }))
                    hl.dispatch(hl.dsp.window.resize({ x = 640, y = 360 }))
                  end''))
                (bind "${mod} + ALT + 1" (exec "${move-active} topLeft"))
                (bind "${mod} + ALT + 2" (exec "${move-active} topRight"))
                (bind "${mod} + ALT + 3" (exec "${move-active} bottomRight"))
                (bind "${mod} + ALT + 4" (exec "${move-active} bottomLeft"))
                (bind "${mod} + ALT + 5" (exec "${move-active} topMiddle"))
                (bind "${mod} + ALT + 6" (exec "${move-active} middleMiddle"))
                (bind "${mod} + ALT + 7" (exec "${move-active} bottomMiddle"))
                (bind "${mod} + P" (dsp "window.pin()"))
                (bind "${mod} + Escape" (exec "${spotlight} power"))
                (bind "${mod} + B" (exec "${spotlight} bluetooth"))
                (bind "${mod} + E" (exec "${spotlight} emoji"))
                (bind "${mod} + SPACE" (exec "${spotlight} app"))
                (bind "${mod} + V" (exec "${spotlight} clipboard"))
                (bind "${mod} + S" (exec "${pkgs.hyprshot}/bin/hyprshot -m region -z --clipboard-only"))
                (bind "${mod} + SHIFT + S" (exec "${pkgs.hyprshot}/bin/hyprshot -m region -z -o ~/Pictures"))
                # Region screenshot → annotate in satty → copy to clipboard.
                (bind "${mod} + CTRL + S" (
                  exec "${pkgs.hyprshot}/bin/hyprshot -m region --raw | ${pkgs.satty}/bin/satty --filename - --copy-command wl-copy"
                ))
                (bind "${mod} + N" (exec "${lib.getExe' pkgs.pkgs-mine.notification-center "notifctl"} -t"))
                (bind "${mod} + C" (exec "${config.programs.mpv.package}/bin/mpv av://v4l2:/dev/video1"))
                (bind "${mod} + SHIFT + M" (dsp "exit()"))
                (bind "${mod} + U" (exec "${pkgs.pkgs-mine.uair-toggle-and-notify}/bin/uair-toggle-and-notify"))
                (bind "${mod} + H" (dsp ''focus({ direction = "left" })''))
                (bind "${mod} + L" (dsp ''focus({ direction = "right" })''))
                (bind "${mod} + J" (dsp ''focus({ direction = "up" })''))
                (bind "${mod} + K" (dsp ''focus({ direction = "down" })''))
                (bind "${mod} + Tab" (dsp "window.cycle_next()"))
                (bind "ALT + R" (dsp ''submap("resize")''))

                # Move/resize windows with mainMod + LMB/RMB and dragging
                (bindWith { mouse = true; } "${mod} + mouse:272" (dsp "window.drag()"))
                (bindWith { mouse = true; } "${mod} + SHIFT + mouse:272" (dsp "window.resize()"))

                (repeating "${mod} + minus" (exec "${move-active} shrink"))
                (repeating "${mod} + SHIFT + minus" (exec "${move-active} grow"))

                # https://github.com/sulmone/X11/blob/master/include/X11/XF86keysym.h
                (repeatingLocked "XF86AudioPlay" (exec "${pkgs.playerctl}/bin/playerctl play-pause"))
                (repeatingLocked "XF86AudioNext" (exec "${pkgs.playerctl}/bin/playerctl next"))
                (repeatingLocked "XF86AudioPrev" (exec "${pkgs.playerctl}/bin/playerctl previous"))
                (repeatingLocked "XF86AudioRaiseVolume" (exec "${pactl} set-sink-volume @DEFAULT_SINK@ +5%"))
                (repeatingLocked "XF86AudioLowerVolume" (exec "${pactl} set-sink-volume @DEFAULT_SINK@ -5%"))
                (locked "XF86AudioMute" (exec "${pactl} set-sink-mute @DEFAULT_SINK@ toggle"))

                # Push-to-talk: unmute on press, mute on release
                (locked "${mod} + A" (exec "${virtual-headset-ctl} unmute"))
                (release "${mod} + A" (exec "${virtual-headset-ctl} mute"))
              ]
              # Switch workspaces with mainMod + [0-9]; move the active window
              # there with mainMod + SHIFT + [0-9]
              ++ lib.concatMap (
                ws:
                let
                  key = toString (lib.mod ws 10);
                in
                [
                  (bind "${mod} + ${key}" (dsp "focus({ workspace = ${toString ws} })"))
                  (bind "${mod} + SHIFT + ${key}" (dsp "window.move({ workspace = ${toString ws} })"))
                ]
              ) (lib.range 1 10);
            };

            submaps.resize.settings.bind = [
              (repeating "right" (dsp "window.resize({ x = 10, y = 0, relative = true })"))
              (repeating "left" (dsp "window.resize({ x = -10, y = 0, relative = true })"))
              (repeating "up" (dsp "window.resize({ x = 0, y = -10, relative = true })"))
              (repeating "down" (dsp "window.resize({ x = 0, y = 10, relative = true })"))
              (repeating "minus" (dsp "window.resize({ x = -128, y = -72, relative = true })"))
              (repeating "SHIFT + minus" (dsp "window.resize({ x = 128, y = 72, relative = true })"))
              (bind "1" (exec "${move-active} topLeft"))
              (bind "2" (exec "${move-active} topRight"))
              (bind "3" (exec "${move-active} bottomRight"))
              (bind "4" (exec "${move-active} bottomLeft"))
              (repeating "l" (dsp "window.move({ x = ${toString gapsNumeric}, y = 0, relative = true })"))
              (repeating "h" (dsp "window.move({ x = -${toString gapsNumeric}, y = 0, relative = true })"))
              (repeating "j" (dsp "window.move({ x = 0, y = ${toString gapsNumeric}, relative = true })"))
              (repeating "k" (dsp "window.move({ x = 0, y = -${toString gapsNumeric}, relative = true })"))
              (bind "escape" (dsp ''submap("reset")''))
            ];
          };
      };
    };
}
