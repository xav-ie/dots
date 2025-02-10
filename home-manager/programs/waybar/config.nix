{
  lib,
  pkgs,
  toplevel,
}:
let
  # "top" or "bottom"
  position = "top";
  margin-top = if position == "top" then 10 else 0;
  margin-bottom = if position == "top" then 0 else 10;
  myPackages = toplevel.self.packages.${pkgs.system};
  get-uair-status = lib.getExe (
    pkgs.writeShellApplication {
      name = "get-uair-status";
      runtimeInputs = [
        pkgs.uair
        myPackages.is-sshed
      ];
      text = ''
        is-sshed || uairctl fetch '{state} {time}' 2>/dev/null
      '';
    }
  );
  writeAudioApplication =
    name: text:
    lib.getExe (
      pkgs.writeShellApplication {
        inherit name text;
        runtimeInputs = with pkgs; [
          pavucontrol
          jq
        ];
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
  "layer" = position;
  "margin-top" = margin-top;
  "margin-bottom" = margin-bottom;
  "margin-left" = 10;
  "margin-right" = 10;
  "position" = "top";
  "modules-left" = [
    "custom/arch"
    "hyprland/workspaces"
  ];
  "modules-center" = [
    "custom/pomodoro"
  ];
  "modules-right" = [
    "custom/privacy-audio"
    "tray"
    "cava"
    "pulseaudio"
    "bluetooth"
    "network"
    "custom/notification"
    "clock"
  ];
  "custom/arch" = {
    "format" = "";
    "tooltip" = false;
    # TODO: use direct path after integrating rofi
    "on-click" = "sh $HOME/.config/rofi/powermenu/type-4/powermenu.sh";
  };
  "hyprland/workspaces" = {
    "format" = "{icon}";
    "on-click" = "activate";
    "tooltip" = "";
    "all-outputs" = true;
    "format-icons" = {
      "active" = "";
      "default" = "";
    };
  };
  "clock" = {
    "format" = "{:%a %m/%d %I:%M}";
    "format-alt" = "{:%H:%M}  ";
    "tooltip-format" = "<tt><small>{calendar}</small></tt>";
    "calendar" = {
      "mode" = "year";
      "mode-mon-col" = 3;
      "weeks-pos" = "right";
      "on-scroll" = 1;
      "on-click-right" = "mode";
      "format" = {
        "months" = "<span color='#ffead3'><b>{}</b></span>";
        "days" = "<span color='#ecc6d9'><b>{}</b></span>";
        "weeks" = "<span color='#99ffdd'><b>W{}</b></span>";
        "weekdays" = "<span color='#ffcc66'><b>{}</b></span>";
        "today" = "<span color='#ff6699'><b><u>{}</u></b></span>";
      };
    };
    "actions" = {
      "on-click-right" = "mode";
      "on-click-forward" = "tz_up";
      "on-click-backward" = "tz_down";
      "on-scroll-up" = "shift_up";
      "on-scroll-down" = "shift_down";
    };
  };
  "tray" = {
    "icon-size" = 22;
    "spacing" = 11;
  };
  "cava" = {
    "framerate" = 60;
    "autosens" = 0;
    "sensitivity" = 5;
    "bars" = 12;
    "lower_cutoff_freq" = 50;
    "higher_cutoff_freq" = 10000;
    "method" = "pulse";
    "source" = "auto";
    "stereo" = false;
    "reverse" = false;
    "bar_delimiter" = 0;
    "monstercat" = true;
    "waves" = true;
    "noise_reduction" = 0.77;
    "input_delay" = 2;
    "format-icons" = [
      "▁"
      "▂"
      "▃"
      "▄"
      "▅"
      "▆"
      "▇"
      "█"
    ];
    "actions" = {
      "on-click-right" = "mode";
    };
  };
  "pulseaudio" = {
    "format" = "<span>{icon}</span> {volume}%";
    "format-muted" = "";
    "tooltip" = false;
    "format-icons" = {
      "headphone" = "";
      "default" = [
        ""
        ""
        "󰕾"
        "󰕾"
        "󰕾"
        ""
        ""
        ""
      ];
    };
    "scroll-step" = 0.5;
    "reverse-scrolling" = true;
    "on-click" = lib.getExe pkgs.pavucontrol;
  };
  "bluetooth" = {
    "format" = "<span></span> {status}";
    "format-disabled" = "";
    "format-connected" = "<span></span>{num_connections}";
    "tooltip-format" = "{device_enumerate}";
    "tooltip-format-enumerate-connected" = "{device_alias}   {device_address}";
  };
  "network" = {
    "interface" = "wlp4s0";
    "format" = "{ifname}";
    "format-wifi" = "<span> </span>{essid}";
    "format-ethernet" = "{ipaddr}/{cidr} ";
    "format-disconnected" = "<span>󰖪 </span>No Network";
    "tooltip-format-wifi" = "{essid} ({signalStrength}%) ";
  };
  "custom/pomodoro" = {
    "format" = "{}";
    "tooltip" = false;
    "on-click" = lib.getExe myPackages.uair-toggle-and-notify;
    "exec" = get-uair-status;
    "interval" = 1;
  };
  "custom/notification" = {
    "format" = "{icon}";
    "format-icons" = {
      "dnd-none" = "";
      "dnd-notification" = "<span foreground='red'><sup></sup></span>";
      "none" = "";
      "notification" = "<span foreground='red'><sup></sup></span>";
    };
    "return-type" = "json";
    "tooltip" = false;
    "exec" = writeNotificationApplication "get-notification-status" "swaync-client -swb";
    "on-click" = writeNotificationApplication "toggle-notification-center" "swaync-client -t -sw";
    "on-click-right" = writeNotificationApplication "toggle-do-not-disturb" "swaync-client -d -sw";
    "escape" = true;
  };
  "custom/privacy-audio" = {
    "format" = "<span></span>{}";
    "exec" =
      writeAudioApplication "get-audio-status" # sh
        ''
          pactl -f json list source-outputs | \
          jq '[.[] | select(.properties."application.name" != "cava")] | length'
        '';
    "tooltip" =
      writeAudioApplication "get-applications-using-audio" # sh
        ''
          pactl -f json list source-outputs | \
          jq -r '.[] | select(.properties."application.name" != "cava") | .properties."application.name"'
        '';
    "tooltip-format" = "{}";
  };
}
