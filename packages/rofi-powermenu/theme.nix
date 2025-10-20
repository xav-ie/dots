{
  lib,
  pkgs,
}:
let
  inherit ((import ../../lib/fonts.nix { inherit lib pkgs; })) fonts;
  monoFont = fonts.name "mono";
  buttonTextSize = 12;
  buttonPaddingSize = 35;
in
''
  configuration {
    show-icons: false;
  }

  * {
    background: #1E2127FF;
    background-alt: #282B31FF;
    foreground: #FFFFFFFF;
    selected: #61AFEFFF;

    mainbox-spacing: 50px;
    mainbox-margin: 50px;
    message-margin: 0px 300px;
    message-padding: 12px;
    message-border-radius: 12px;
    listview-spacing: 25px;
    element-padding: ${
      toString (buttonPaddingSize - buttonTextSize)
    }px 0px ${toString buttonPaddingSize}px 0px;
    element-border-radius: 60px;

    prompt-font: "${monoFont} Bold 48";
    textbox-font: "${monoFont} ${toString buttonTextSize}";
    element-text-font: "feather 48";

    background-window: black/20%;
    background-normal: white/5%;
    background-selected: white/15%;
    foreground-normal: white;
    foreground-selected: white;
  }

  window {
    transparency: "real";
    location: center;
    anchor: center;
    fullscreen: false;
    width: 1000px;
    border-radius: 50px;
    cursor: "default";
    background-color: var(background-window);
  }

  mainbox {
    enabled: true;
    spacing: var(mainbox-spacing);
    margin: var(mainbox-margin);
    background-color: transparent;
    children: [ "dummy", "inputbar", "listview", "message", "dummy" ];
  }

  inputbar {
    enabled: true;
    background-color: transparent;
    children: [ "dummy", "prompt", "dummy" ];
  }

  dummy {
    background-color: transparent;
  }

  prompt {
    enabled: true;
    font: var(prompt-font);
    background-color: transparent;
    text-color: var(foreground-normal);
  }

  message {
    enabled: true;
    margin: var(message-margin);
    padding: var(message-padding);
    border-radius: var(message-border-radius);
    background-color: var(background-normal);
    text-color: var(foreground-normal);
  }

  textbox {
    font: var(textbox-font);
    background-color: transparent;
    text-color: inherit;
    vertical-align: 0.5;
    horizontal-align: 0.5;
  }

  listview {
    enabled: true;
    expand: false;
    columns: 5;
    lines: 1;
    cycle: true;
    dynamic: true;
    scrollbar: false;
    layout: vertical;
    reverse: false;
    fixed-height: true;
    fixed-columns: false;
    spacing: var(listview-spacing);
    background-color: transparent;
    cursor: "default";
  }

  element {
    enabled: true;
    padding: var(element-padding);
    border-radius: var(element-border-radius);
    background-color: var(background-normal);
    text-color: var(foreground-normal);
    cursor: pointer;
    vertical-align: 0.5;
  }

  element-text {
    font: var(element-text-font);
    background-color: transparent;
    text-color: inherit;
    cursor: inherit;
    vertical-align: 0.5;
    horizontal-align: 0.5;
  }

  element selected.normal {
    background-color: var(background-selected);
    text-color: var(foreground-selected);
  }
''
