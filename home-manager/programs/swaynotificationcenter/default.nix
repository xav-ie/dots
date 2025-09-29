{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.swaync;
in
{
  options.services.swaync = {
    notificationHeight = lib.mkOption {
      default = 85;
      type = lib.types.ints.positive;
      description = "Height of a single notification in pixels";
    };
    notificationWidth = lib.mkOption {
      default = 680;
      type = lib.types.ints.positive;
      description = "Width of notification windows in pixels";
    };
    controlCenterWidth = lib.mkOption {
      default = 900;
      type = lib.types.ints.positive;
      description = "Width of the control center in pixels";
    };
    controlCenterHeight = lib.mkOption {
      default = 1200;
      type = lib.types.ints.positive;
      description = "Height of the control center in pixels";
    };
  };

  config = {
    home.packages = [ config.services.swaync.package ];

    services.swaync =
      let
        timeout = 10;
        timeout-critical = 0;
        timeout-low = 5;
        max-timeout = lib.max (lib.max timeout timeout-critical) timeout-low;
        # do not count 0, that is actually infinity
        not0 = thing: if thing == 0 then max-timeout else thing;
        min-timeout = lib.min (lib.min (not0 timeout) (not0 timeout-critical)) (not0 timeout-low);
      in
      {
        enable = true;
        settings = {
          "$schema" = "${pkgs.swaynotificationcenter.outPath}/etc/xdg/swaync/configSchema.json";
          inherit timeout timeout-critical timeout-low;
          control-center-exclusive-zone = true;
          control-center-height = cfg.controlCenterHeight;
          control-center-layer = "overlay";
          control-center-margin-bottom = 0;
          control-center-margin-left = 0;
          control-center-margin-right = 0;
          control-center-margin-top = 0;
          control-center-positionX = "none";
          control-center-positionY = "none";
          control-center-width = cfg.controlCenterWidth;
          cssPriority = "user";
          fit-to-screen = false;
          hide-on-action = true;
          hide-on-clear = true;
          image-visibility = "when-available";
          keyboard-shortcuts = true;
          layer = "overlay";
          layer-shell = false;
          notification-2fa-action = true;
          notification-body-image-height = 100;
          notification-body-image-width = 200;
          notification-icon-size = 64;
          notification-inline-replies = true;
          notification-window-width = cfg.notificationWidth;
          notification-window-height = cfg.notificationHeight;
          notification-grouping = false;
          positionX = "right";
          positionY = "top";
          relative-timestamps = true;
          script-fail-notify = true;
          scripts = {
            reposition = {
              exec = lib.getExe (
                pkgs.writeNuApplication {
                  name = "fix-notification-position";
                  runtimeInputs = [
                    pkgs.pkgs-mine.move-active
                    config.services.swaync.package
                    pkgs.hyprland
                  ];
                  text = # nu
                    ''
                      # Count file to track visible notifications
                      let count_file = "/tmp/swaync-visible-count"

                      # Initialize count file if it doesn't exist
                      if not ($count_file | path exists) {
                        "0" | save $count_file
                      }

                      # Increment the count for new notification
                      let current_count = (open $count_file | into int)
                      let new_count = $current_count + 1
                      ($new_count | into string) | save -f $count_file

                      # Calculate and set initial height
                      let notification_height = ${toString cfg.notificationHeight}
                      let calculated_height = ($new_count * $notification_height)
                      let height = if $calculated_height < $notification_height { $notification_height } else if $calculated_height > 600 { 600 } else { $calculated_height }

                      # Resize the swaync window
                      hyprctl dispatch resizewindowpixel $"exact ${toString cfg.notificationWidth} ($height),class:^swaync$"

                      # Then reposition as before
                      def currentPrimaryJob [id: number] {
                        let relevantJobs = (job list
                                            | where tag == "spamMoveNotification"
                                            | sort-by id)
                        if (($relevantJobs | length) == 0) {
                          return false
                        }
                        let firstRunningJobId = ($relevantJobs | first | get id)
                        print $"First running ($firstRunningJobId)"
                        $firstRunningJobId == $id
                      }
                      job spawn { move-active topRight "title:swaync" | complete }

                      # For normal notifications, wait the full timeout then decrement
                      # We spawn this immediately to track the actual timeout
                      job spawn --tag notificationTimeout { ||
                        # Wait for the actual notification timeout (10 seconds for normal)
                        sleep ${toString timeout-low}sec

                        # After timeout, decrement the count
                        let count_file = "/tmp/swaync-visible-count"
                        let current_count = (open $count_file | into int)
                        let new_count = if $current_count > 0 { $current_count - 1 } else { 0 }
                        ($new_count | into string) | save -f $count_file

                        # Calculate new height after decrement
                        let notification_height = ${toString cfg.notificationHeight}
                        let calculated_height = ($new_count * $notification_height)
                        let final_height = if $calculated_height < $notification_height { $notification_height } else if $calculated_height > 600 { 600 } else { $calculated_height }

                        # Resize to new height
                        hyprctl dispatch resizewindowpixel $"exact ${toString cfg.notificationWidth} ($final_height),class:^swaync$"
                      }

                      # Keep repositioning for a bit after min timeout
                      sleep ("${toString min-timeout}sec" | into duration)
                      job spawn --tag spamMoveNotification { ||
                        # spam repositioning for a bit
                        let currentId = (job id)
                        mut timeLeft = ${toString (lib.max 0 (max-timeout - min-timeout))} | into float
                        while $timeLeft >= 0.0 {
                          let chunk = 0.25
                          sleep ($"($chunk)sec" | into duration)
                          $timeLeft = $timeLeft - $chunk
                          # prevent contention of move-active
                          if (currentPrimaryJob $currentId) {
                            move-active topRight "title:swaync"
                          }
                        }

                        # This job is just for repositioning now
                      }
                      # ensure job spawn completion
                      sleep ${toString max-timeout}sec
                    '';
                }
              );
              run-on = "receive";
            };
          };
          transition-time = 200;
          widgets = [
            "dnd"
            "mpris"
            "notifications"
          ];
          widget-config = {
            title = {
              text = "Notifications";
              clear-all-button = true;
              button-text = "Clear All";
            };
            dnd = {
              text = "";
            };
            label = {
              max-lines = 5;
              text = "Label Text";
            };
            mpris = {
              image-size = 96;
              image-radius = 12;
            };
          };
        };

        style = # scss
          ''
            /* vim: ft=less */
            * {
              color: white;
              border-radius: 0;
              margin: 0;
              padding: 0;
              box-shadow: none;
            }
            *:hover {
              box-shadow: none;
            }

            @define-color cc-bg rgba(19,6,10,0.65);
            @define-color default-border #631f33;

            @define-color noti-border-color rgba(0, 0, 0, 0.0);
            @define-color noti-bg rgba(19,6,10,0.65);
            @define-color noti-hover-bg rgba(255, 255, 255, 0.1);
            @define-color noti-close-bg rgba(255, 255, 255, 0.1);
            @define-color noti-close-bg-hover rgba(255, 255, 255, 0.15);

            @define-color bg-selected rgb(19,6,10,1);

            .notification-row {
              outline: none;
            }

            .control-center .notification-row:focus,
            .control-center .notification-row:hover {
              opacity: 1;
            }

            .notification-row:focus .notification,
            .notification-row:hover .notification {
              box-shadow: none;
            }

            .control-center .notification {
              box-shadow: none;
              margin: 15px 20px;
              border: 4px solid @default-border;
              border-radius: 12px;
            }

            .notification {
              margin: 0;
              background: transparent;
              border-radius: 0;
              min-height: ${toString cfg.notificationHeight}px;
            }
            .notification:hover {
              background: @noti-hover-bg;
            }

            /* Uncomment to enable specific urgency colors
            .low {
              background: yellow;
              padding: 6px;
              border-radius: 12px;
            }

            .normal {
              background: green;
              padding: 6px;
              border-radius: 12px;
            }

            .critical {
              background: red;
              padding: 6px;
              border-radius: 12px;
            }
            */

            .notification-content {
              background: transparent;
              margin: 0;
              padding: 10px;
              border-radius: 0;
            }
            .notification-content .horizontal {
              padding: 0;
              margin: 0;
            }
            .notification-content .horizontal .horizontal {
              padding: 0;
              margin: 0;
            }

            .notification-content .horizontal .vertical {
              padding: 0;
              margin: 0;
            }

            .close-button {
              background: @default-border;
              color: white;
              text-shadow: none;
              padding: 0;
              border-radius: 100%;
              margin-top: 10px;
              margin-right: 10px;
              box-shadow: none;
              border: none;
              min-width: 32px;
              min-height: 32px;
            }

            .close-button:hover {
              box-shadow: none;
            }

            .notification-default-action,
            .notification-action {
              padding: 0;
              margin: 0;
              box-shadow: none;
              background: transparent;
              border: none;
              color: white;
              border-radius: 0;
              border-radius: 0;
            }

            .notification-default-action:hover,
            .notification-action:hover {
              -gtk-icon-effect: none;
              background-color: transparent;
            }

            /* When alternative actions are visible */
            .notification-default-action:not(:only-child) {
              border-bottom-left-radius: 0;
              border-bottom-right-radius: 0;
            }

            .notification-action {
              border-radius: 0;
              border-top: none;
              border-right: none;
            }

            /* add bottom border radius to eliminate clipping */
            .notification-action:first-child {
              border-bottom-left-radius: 0;
            }

            .notification-action:last-child {
              border-bottom-right-radius: 0;
              border-right: none;
            }

            .notification-content .image {
              border-radius: 12px;
              padding: 0;
              margin-right: 10px;
            }

            /* Add spacing by pushing the text away from the image area */
            .app-icon {
              margin-right: 10px;
            }

            .body-image {
              background-color: white;
              border-radius: 12px;
              border: 3px solid pink;
            }

            /* Notification title text */
            .summary {
              font-size: 16px;
              font-weight: bold;
              background: transparent;
              color: white;
              text-shadow: none;
            }

            /* Notification timestamp */
            .time {
              font-size: 16px;
              font-weight: bold;
              background: transparent;
              color: white;
              text-shadow: none;
            }

            /* Notification body */
            .body {
              font-size: 15px;
              font-weight: normal;
              background: transparent;
              color: white;
              text-shadow: none;
            }

            .control-center {
              background: @cc-bg;
              background-clip: border-box;
            }

            .control-center-list {
              background: transparent;
            }
            .control-center-list:hover {
              background: transparent;
            }

            .control-center-list-placeholder {
              opacity: 0.5;
            }

            .floating-notifications {
              background: @noti-bg;
            }

            /* Window behind control center and on all other monitors */
            .blank-window {
              background: transparent;
            }

            /*** Widgets ***/

            /* Title widget */
            .widget-title {
              font-size: 1.5rem;
            }
            .widget-title > button {
              font-size: initial;
              color: white;
              text-shadow: none;
              background: blue;
              box-shadow: none;
              border-radius: 12px;
            }
            .widget-title > button:hover {
              background-color: transparent;
            }

            /* DND widget */
            .widget-dnd {
              font-size: 1.1rem;
              margin: 20px;
              margin-bottom: 0;
              padding: 0;
            }
            .widget-dnd > switch {
              font-size: initial;
              border-radius: 100px;
              background-color: transparent;
              border: 4px solid @default-border;
              box-shadow: none;
            }
            .widget-dnd > switch:checked {
              background: @bg-selected;
            }
            .widget-dnd > switch:checked slider {
              margin-right: -1px;
              margin-left: 0;
            }
            .widget-dnd > switch slider {
              background-color: transparent;
              border-radius: 100px;
              border: 5px solid @default-border;
              box-shadow: none;
              margin-right: 0;
              margin-left: -1px;
            }

            /* Label widget */
            .widget-label > label {
              font-size: 1.1rem;
            }

            /* Mpris widget */
            .widget-mpris {
              /* The parent to all players */
              margin: 20px;
              margin-bottom: 0;
              padding: 0;
            }
            .widget-mpris-player {
              /* border: 4px solid @default-border; */
              border-radius: 12px;
              background-color: red;
              background-color: transparent;
              box-shadow: none;
              padding: 0;
              margin: 0;
            }
            .widget-mpris-album-art {
              padding: 20px;
              border-radius: 12px;
              box-shadow: none;
            }
            /* The media player buttons (play, pause, next, etc...) */
            .widget-mpris-player button {
              margin-bottom: 20px;
            }
            .widget-mpris-player button:hover {
              background: transparent;
            }
            .widget-mpris > box > button {
              /* Change player side buttions */
              transition: opacity 0.2s ease-in-out;
            }
            .widget-mpris > box > button:disabled {
              /* Change player side buttions insensitive */
              opacity: 0;
            }
            .widget-mpris-title {
              font-weight: bold;
              font-size: 1.25rem;
            }
            .widget-mpris-subtitle {
              font-size: 1.1rem;
            }
            carouselindicatordots {
              background: green;
            }
            /* Buttons widget */
            .widget-buttons-grid {
              border-radius: 12px;
              background: transparent;
            }

            .widget-buttons-grid > flowbox > flowboxchild > button {
              background: transparent;
              border-radius: 12px;
            }

            .widget-buttons-grid > flowbox > flowboxchild > button:hover {
              background: transparent;
            }

            /* Menubar widget */
            .widget-menubar > box > .menu-button-bar > button {
              border: none;
              background: transparent;
              background: red;
            }

            .topbar-buttons > button {
              /* Name defined in config after # */
              border: none;
              background: transparent;
              background: blue;
            }

            /* Volume widget */

            .widget-backlight,
            .widget-volume {
              background: transparent;
              padding: 0;
              margin: 0;
              border-radius: 12px;
            }

            /* Title widget */
            .widget-inhibitors {
              font-size: 1.5rem;
            }
            .widget-inhibitors > button {
              font-size: initial;
              color: red;
              text-shadow: none;
              background: transparent;
              border: 1px solid @noti-border-color;
              box-shadow: none;
              border-radius: 12px;
            }
            .widget-inhibitors > button:hover {
              background: transparent;
            }

            .notification-group {
              background: transparent;
            }
            .notification-group:hover {
              background: transparent;
            }

            /* Notification group headers (title) */
            .notification-group-headers {
              margin: 20px 20px;
              margin-bottom: 0;
            }

            /* Notification group buttons container */
            .notification-group-buttons {
              margin: 20px 20px;
              margin-bottom: 0;
            }

            /* Notification group buttons (clear all and collapse/expand) */
            .notification-group-close-all-button.circular,
            .notification-group-collapse-button.circular {
              min-width: 36px;
              min-height: 36px;
              border: 4px solid @default-border;
              border-radius: 12px;
              margin: 0;
              background: transparent;
            }
            .notification-group-close-all-button.circular:hover,
            .notification-group-collapse-button.circular:hover {
              background: @noti-hover-bg;
            }

            /* Add spacing only between the buttons */
            .notification-group-collapse-button.circular {
              margin-right: 4px;
            }
          '';
      };
  };
}
