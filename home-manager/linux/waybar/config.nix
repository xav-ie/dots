{
  config,
  lib,
  pkgs,
}:
let
  cfg = config.programs.waybar;
  hyprCfg = config.programs.hyprland;
  marginAmount = hyprCfg.gapsNumeric;
  # "top" or "bottom"
  position = "top";
  margin-top = if position == "top" then marginAmount else 0;
  margin-bottom = if position == "top" then 0 else marginAmount;

  # Cava visualizer bar characters (0-7 levels)
  cavaBars = [
    "▁"
    "▂"
    "▃"
    "▄"
    "▅"
    "▆"
    "▇"
    "█"
  ];
  cavaSedCmd = lib.concatStrings (
    [ "s/;//g" ] ++ lib.imap0 (i: bar: ";s/${toString i}/${bar}/g") cavaBars
  );
  cavaExec =
    conf:
    lib.getExe (
      pkgs.writeShellApplication {
        name = "cava-waybar";
        runtimeInputs = [
          pkgs.cava
          pkgs.coreutils
        ];
        text = ''
          cava -p ${conf} | stdbuf -oL tr -d '\0' | stdbuf -oL sed -u '${cavaSedCmd}'
        '';
      }
    );
  get-uair-status = lib.getExe (
    pkgs.writeShellApplication {
      name = "get-uair-status";
      runtimeInputs = [
        pkgs.uair
        pkgs.pkgs-mine.is-sshed
      ];
      text = ''
        [[ "$(is-sshed)" == "false" ]] && uairctl fetch '{state} {time}' 2>/dev/null
      '';
    }
  );
  writeNotificationApplication =
    name: text:
    lib.getExe (
      pkgs.writeShellApplication {
        inherit name text;
        runtimeInputs = with pkgs; [
          swaynotificationcenter
        ];
      }
    );
in
{
  height = cfg.barHeight;
  layer = position;
  inherit margin-top;
  inherit margin-bottom;
  margin-left = marginAmount;
  margin-right = marginAmount;
  position = "top";
  modules-left = [
    "custom/arch"
    "hyprland/workspaces"
  ];
  modules-center = [
    "custom/pomodoro"
  ];
  modules-right = [
    "tray"
    "custom/cava"
    "wireplumber"
    "custom/cava-mic"
    "custom/virtual-headset"
    "custom/bluetooth"
    "custom/network"
    "custom/notification"
    "clock"
  ];
  "custom/arch" = {
    format = "";
    tooltip = false;
    on-click = lib.getExe pkgs.pkgs-mine.rofi-powermenu;
  };
  "hyprland/workspaces" = {
    format = "{icon}";
    on-click = "activate";
    tooltip = "";
    all-outputs = true;
    format-icons = {
      active = "";
      default = "";
    };
  };
  clock = {
    format = "{:%a %m/%d %I:%M}";
    format-alt = "{:%H:%M}  ";
    tooltip-format = "<tt><small>{calendar}</small></tt>";
    calendar = {
      mode = "year";
      mode-mon-col = 3;
      weeks-pos = "right";
      on-scroll = 1;
      on-click-right = "mode";
      format = {
        months = "<span color='#ffead3'><b>{}</b></span>";
        days = "<span color='#ecc6d9'><b>{}</b></span>";
        weeks = "<span color='#99ffdd'><b>W{}</b></span>";
        weekdays = "<span color='#ffcc66'><b>{}</b></span>";
        today = "<span color='#ff6699'><b><u>{}</u></b></span>";
      };
    };
    actions = {
      on-click-right = "mode";
      on-click-forward = "tz_up";
      on-click-backward = "tz_down";
      on-scroll-up = "shift_up";
      on-scroll-down = "shift_down";
    };
  };
  tray = {
    icon-size = 22;
    spacing = 11;
  };
  "custom/cava" = {
    exec = cavaExec ./cava-speaker.conf;
    format = "{}";
    tooltip = false;
  };
  "custom/cava-mic" = {
    exec = cavaExec ./cava-mic.conf;
    format = "{}";
    tooltip = false;
  };
  wireplumber = {
    format = "<span>{icon}</span> {volume}%";
    format-muted = "";
    # tooltip = false;
    format-icons = [
      " "
      " "
      " "
      " "
      " "
      " "
      " "
    ];
    scroll-step = 0.5;
    reverse-scrolling = true;
    on-click = lib.getExe pkgs.pavucontrol;
  };
  "custom/network" = {
    format = "{}";
    interval = 5;
    return-type = "json";
    exec = lib.getExe (
      pkgs.writeNuApplication {
        name = "waybar-network-status";
        runtimeInputs = with pkgs; [
          iproute2
          wirelesstools
        ];
        text = builtins.readFile ./waybar-network-status.nu;
      }
    );
  };
  "custom/pomodoro" = {
    format = "{}";
    tooltip = false;
    on-click = lib.getExe pkgs.pkgs-mine.uair-toggle-and-notify;
    exec = get-uair-status;
    interval = 1;
  };
  "custom/notification" = {
    format = "{icon}";
    format-icons = {
      dnd-none = "";
      dnd-notification = "<span foreground='red'><sup></sup></span>";
      none = "";
      notification = "<span foreground='red'><sup></sup></span>";
    };
    return-type = "json";
    tooltip = false;
    exec = writeNotificationApplication "get-notification-status" "swaync-client -swb";
    on-click = writeNotificationApplication "toggle-notification-center" "swaync-client -t -sw";
    on-click-right = writeNotificationApplication "toggle-do-not-disturb" "swaync-client -d -sw";
    escape = true;
  };
  "custom/bluetooth" = {
    format = "{}";
    interval = 5;
    return-type = "json";
    exec = lib.getExe (
      pkgs.writeNuApplication {
        name = "waybar-bluetooth-status";
        runtimeInputs = with pkgs; [
          util-linux
          bluez
        ];
        text = builtins.readFile ./waybar-bluetooth-status.nu;
      }
    );
    on-click = lib.getExe (
      pkgs.writeNuApplication {
        name = "waybar-bluetooth-toggle";
        runtimeInputs = [ pkgs.util-linux ];
        text = # nu
          ''
            let status = (rfkill list bluetooth | lines | find "Soft blocked" | str trim | split column ": " | get column2.0 | ansi strip)
            if $status == "no" {
              rfkill block bluetooth
            } else {
              rfkill unblock bluetooth
            }
          '';
      }
    );
  };
}
