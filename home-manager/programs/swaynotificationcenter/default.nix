{ pkgs, ... }:
{
  config = {
    home.packages = [ pkgs.swaynotificationcenter ];
    # this does not seem to create the folders necessary...
    home.file.".config/swaync/config.json".text = # json
      ''
        {
          "$schema": "${pkgs.swaynotificationcenter.outPath}/etc/xdg/swaync/configSchema.json",
          "control-center-exclusive-zone": true,
          "control-center-height": 1200,
          "control-center-layer": "overlay",
          "control-center-margin-bottom": 0,
          "control-center-margin-left": 0,
          "control-center-margin-right": 0,
          "control-center-margin-top": 0,
          "control-center-positionX": "none",
          "control-center-positionY": "none",
          "control-center-width": 900,
          "cssPriority": "user",
          "fit-to-screen": false,
          "hide-on-action": true,
          "hide-on-clear": true,
          "image-visibility": "when-available",
          "keyboard-shortcuts": true,
          "layer": "overlay",
          "layer-shell": false,
          "notification-2fa-action": true,
          "notification-body-image-height": 100,
          "notification-body-image-width": 200,
          "notification-icon-size": 64,
          "notification-inline-replies": true,
          "notification-window-width": 680,
          "positionX": "right",
          "positionY": "top",
          "relative-timestamps": true,
          "script-fail-notify": true,
          "timeout": 10,
          "timeout-critical": 0,
          "timeout-low": 5,
          "transition-time": 200,
          "widgets": ["dnd", "mpris", "notifications"],
          "widget-config": {
            "title": {
              "text": "Notifications",
              "clear-all-button": true,
              "button-text": "Clear All"
            },
            "dnd": {
              "text": ""
            },
            "label": {
              "max-lines": 5,
              "text": "Label Text"
            },
            "mpris": {
              "image-size": 96,
              "image-radius": 12
            }
          }
        }
      '';
    # I am not sure how I would use sed on this file now that is in nix...
    home.file.".config/swaync/style.css".text = # css
      ''
        /* vim: ft=less */

        @define-color cc-bg rgba(19,6,10,0.65);
        @define-color default-border #631f33;

        @define-color noti-border-color rgba(0, 0, 0, 0.0);
        @define-color noti-bg rgba(255, 255, 0, 0.65);
        @define-color noti-bg-hover rgba(65, 65, 65, 0.8);
        @define-color noti-bg-focus rgba(68, 68, 68, 0.6);
        @define-color noti-close-bg rgba(255, 255, 255, 0.1);
        @define-color noti-close-bg-hover rgba(255, 255, 255, 0.15);

        @define-color mpris-album-art-overlay rgba(255, 0, 0, 0.95);
        @define-color mpris-button-hover rgba(0, 255, 0, 0.50);

        @define-color bg-selected rgb(0, 128, 255);


        .notification-row {
          /* transition: all 200ms ease; */
          outline: none;
          /*margin-bottom: 4px;*/
          border-radius: 12px;
        }
        .notification-row:hover {
          background: transparent;
        }

        .control-center .notification-row:focus,
        .control-center .notification-row:hover {
          opacity: 1;
          background: transparent;
        }

        .notification-row:focus .notification,
        .notification-row:hover .notification {
          box-shadow: none;
        }

        .control-center .notification {
          box-shadow: none;
          margin: 20px 20px;
          margin-bottom: 0;
          border: 4px solid @default-border;
          border-radius: 12px;
        }

        /*.control-center .notification-row {
          opacity: 0.5;
        }*/

        .notification {
          /* transition: all 200ms ease; */
          margin: 0;
          /* padding: 10px; */
          background: transparent;
          border-radius: 0;
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

        /* TODO: how do I get rid of this! */
        .notification-content .horizontal .vertical {
          /* border: 3px solid cyan; */
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
          min-width: 24px;
          min-height: 24px;
        }

        .close-button:hover {
          box-shadow: none;
          /* transition: all 0.15s ease-in-out; */
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
          /* transition: all 200ms ease; */
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

        .image {
          /* border: 3px solid green; */
          padding: 0;
          margin: 0;
        }

        .body-image {
          /*margin-top: 6px;*/
          background-color: white;
          border-radius: 12px;
          border: 3px solid pink;
        }

        .summary {
          font-size: 16px;
          font-weight: bold;
          background: transparent;
          color: white;
          text-shadow: none;
          /* border: 3px solid orange; */
        }

        .time {
          font-size: 16px;
          font-weight: bold;
          background: transparent;
          color: white;
          text-shadow: none;
          /* margin-right: 18px; */
          /* border: 3px solid purple; */
        }

        .body {
          font-size: 15px;
          font-weight: normal;
          background: transparent;
          color: white;
          text-shadow: none;
          /* border: 3px solid yellow; */
        }

        .control-center {
          background: @cc-bg;
          background-clip: border-box;
        }

        .control-center-list {
          background: transparent;
        }

        .control-center-list-placeholder {
          opacity: 0.5;
        }

        .floating-notifications {
          background: transparent;
        }

        /* Window behind control center and on all other monitors */
        .blank-window {
          background: transparent;
        }


        /*** Widgets ***/

        /* Title widget */
        .widget-title {
          /*margin: 8px;*/
          font-size: 1.5rem;
        }
        .widget-title > button {
          font-size: initial;
          color: white;
          text-shadow: none;
          /* background: @noti-bg; */
          background: blue;
          /* background-color: transparent; */
          /* border: 1px solid @noti-border-color; */
          box-shadow: none;
          border-radius: 12px;
        }
        .widget-title > button:hover {
          /* background: @noti-bg-hover; */
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
          /* background: @bg-selected; */
          background: blue;
        }
        .widget-dnd > switch:checked slider {
          /* background: @bg-selected; */
          margin-right: -1px;
          margin-left: 0;
        }
        .widget-dnd > switch slider {
          /* background: @noti-bg-hover; */
          background-color: transparent;
          border-radius: 100px;
          border: 5px solid @default-border;
          box-shadow: none;
          margin-right: 0;
          margin-left: -1px;
        }

        /* Label widget */
        .widget-label {
          /*margin: 8px;*/
        }
        .widget-label > label {
          font-size: 1.1rem;
        }

        /* Mpris widget */
        .widget-mpris {
          /* The parent to all players */
          border: 4px solid @default-border;
          margin: 20px;
          margin-bottom: 0;
          border-radius: 12px;
          padding: 15px;
          padding-top: 35px;
        }
        .widget-mpris-player {
          padding: 0;
          margin: 0;
          background-color: @mpris-album-art-overlay;
          background-color: transparent;
          box-shadow: none;
        }
        .widget-mpris-album-art {
          border-radius: 12px;
          box-shadow: none;
        }
        .widget-mpris-player button:hover {
          /* The media player buttons (play, pause, next, etc...) */
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
          /*padding: 8px;*/
          /*margin: 8px;*/
          border-radius: 12px;
          /* background-color: @noti-bg; */
          background: transparent;
        }

        .widget-buttons-grid>flowbox>flowboxchild>button{
          /* background: @noti-bg; */
          background: transparent;
          border-radius: 12px;
        }

        .widget-buttons-grid>flowbox>flowboxchild>button:hover {
          /* background: @noti-bg-hover; */
          background: transparent;
        }

        /* Menubar widget */
        .widget-menubar>box>.menu-button-bar>button {
          border: none;
          background: transparent;
          background: red;
        }

        /* .AnyName { Name defined in config after #
         *   background-color: @noti-bg;
         *   padding: 8px;
         *   margin: 8px;
         *   border-radius: 12px;
         * }
         *
         * .AnyName>button {
         *   background: transparent;
         *   border: none;
         * }
         *
         * .AnyName>button:hover {
         *   background-color: @noti-bg-hover;
         * }
         */

        .topbar-buttons>button { /* Name defined in config after # */
          border: none;
          background: transparent;
          background: blue;
        }

        /* Volume widget */

        .widget-backlight,
        .widget-volume {
          /* background-color: @noti-bg; */
          background: transparent;
          padding: 0;
          margin: 0;
          border-radius: 12px;
        }

        /* Title widget */
        .widget-inhibitors {
          /*margin: 8px;*/
          font-size: 1.5rem;
        }
        .widget-inhibitors > button {
          font-size: initial;
          color: red;
          text-shadow: none;
          /* background: @noti-bg; */
          background: transparent;
          border: 1px solid @noti-border-color;
          box-shadow: none;
          border-radius: 12px;
        }
        .widget-inhibitors > button:hover {
          /* background: @noti-bg-hover; */
          background: transparent;
        }
        * {
          color: white;
          border-radius: 0;
          margin: 0;
          padding: 0;
          box-shadow: none;
        }
      '';
  };
}
