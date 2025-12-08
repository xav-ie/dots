{
  lib,
  pkgs,
  config,
  ...
}:
let
  inherit ((import ../../../lib/fonts.nix { inherit lib pkgs; })) fonts;
  inherit (config.lib.formats.rasi) mkLiteral;

  # OneDark color scheme
  colors = {
    background = mkLiteral "#1E2127FF";
    background-alt = mkLiteral "#282B31FF";
    foreground = mkLiteral "#FFFFFFFF";
    selected = mkLiteral "#61AFEFFF";
    active = mkLiteral "#98C379FF";
    urgent = mkLiteral "#E06C75FF";
  };

  rofiFont = "${fonts.name "mono"} 16";
in
{
  config = {
    programs.rofi = {
      enable = true;

      font = rofiFont;

      extraConfig = {
        modi = "drun,run,filebrowser,window";
        case-sensitive = false;
        cycle = true;
        filter = "";
        scroll-method = 0;
        normalize-match = true;
        show-icons = true;
        icon-theme = "Papirus";
        steal-focus = false;

        matching = "fuzzy";
        tokenize = true;

        ssh-client = "ssh";
        ssh-command = "{terminal} -e {ssh-client} {host} [-p {port}]";
        parse-hosts = true;
        parse-known-hosts = true;

        drun-categories = "";
        drun-match-fields = "name,generic,exec,categories,keywords";
        drun-display-format = "{name} [<span weight='light' size='small'><i>({generic})</i></span>]";
        drun-show-actions = false;
        drun-url-launcher = "xdg-open";
        drun-use-desktop-cache = false;
        drun-reload-desktop-cache = false;

        run-command = "{cmd}";
        run-list-command = "";
        run-shell-command = "{terminal} -e {cmd}";

        window-match-fields = "title,class";
        window-format = "{t} - {c}";
        window-thumbnail = false;

        disable-history = false;
        sorting-method = "fzf";
        max-history-size = 25;

        display-window = "Windows";
        display-windowcd = "Window CD";
        display-run = "Run";
        display-ssh = "SSH";
        display-drun = "Apps";
        display-combi = "Combi";
        display-keys = "Keys";
        display-filebrowser = "Files";

        terminal = "rofi-sensible-terminal";
        sort = true;
        threads = 0;
        click-to-exit = true;
      };

      theme = {
        "*" = colors // {
          font = rofiFont;
        };

        window = {
          transparency = "real";
          location = mkLiteral "center";
          anchor = mkLiteral "center";
          fullscreen = false;
          width = mkLiteral "1000px";
          x-offset = mkLiteral "0px";
          y-offset = mkLiteral "0px";
          enabled = true;
          margin = mkLiteral "0px";
          padding = mkLiteral "0px";
          border = mkLiteral "0px solid";
          border-radius = mkLiteral "12px";
          border-color = mkLiteral "@selected";
          background-color = mkLiteral "black / 10%";
          cursor = "default";
        };

        mainbox = {
          enabled = true;
          spacing = mkLiteral "20px";
          margin = mkLiteral "0px";
          padding = mkLiteral "20px";
          border = mkLiteral "0px solid";
          border-radius = mkLiteral "0px 0px 0px 0px";
          border-color = mkLiteral "@selected";
          background-color = mkLiteral "rgba(0,0,0,0.5)";
          children = map mkLiteral [
            "inputbar"
            "listview"
          ];
        };

        inputbar = {
          enabled = true;
          spacing = mkLiteral "10px";
          margin = mkLiteral "0px";
          padding = mkLiteral "15px";
          border = mkLiteral "0px solid";
          border-radius = mkLiteral "10px";
          border-color = mkLiteral "@selected";
          background-color = mkLiteral "white / 5%";
          text-color = mkLiteral "@foreground";
          children = map mkLiteral [
            "prompt"
            "entry"
          ];
        };

        prompt = {
          enabled = true;
          background-color = mkLiteral "transparent";
          text-color = mkLiteral "inherit";
        };

        textbox-prompt-colon = {
          enabled = true;
          expand = false;
          str = "::";
          background-color = mkLiteral "transparent";
          text-color = mkLiteral "inherit";
        };

        entry = {
          enabled = true;
          background-color = mkLiteral "transparent";
          text-color = mkLiteral "inherit";
          cursor = mkLiteral "text";
          placeholder = "Search";
          placeholder-color = mkLiteral "inherit";
        };

        listview = {
          enabled = true;
          columns = 1;
          lines = 5;
          cycle = true;
          dynamic = true;
          scrollbar = false;
          layout = mkLiteral "vertical";
          reverse = false;
          fixed-height = true;
          fixed-columns = true;
          spacing = mkLiteral "0px";
          margin = mkLiteral "0px";
          padding = mkLiteral "0px";
          border = mkLiteral "0px solid";
          border-radius = mkLiteral "0px";
          border-color = mkLiteral "@selected";
          background-color = mkLiteral "transparent";
          text-color = mkLiteral "@foreground";
          cursor = "default";
        };

        scrollbar = {
          handle-width = mkLiteral "5px";
          handle-color = mkLiteral "@selected";
          border-radius = mkLiteral "0px";
          background-color = mkLiteral "@background-alt";
        };

        element = {
          enabled = true;
          spacing = mkLiteral "0px";
          margin = mkLiteral "0px";
          padding = mkLiteral "2.5px";
          border = mkLiteral "0px solid";
          border-radius = mkLiteral "10px";
          border-color = mkLiteral "@selected";
          background-color = mkLiteral "transparent";
          text-color = mkLiteral "@foreground";
          orientation = mkLiteral "horizontal";
          cursor = mkLiteral "pointer";
        };

        "element normal.normal" = {
          background-color = mkLiteral "transparent";
          text-color = mkLiteral "@foreground";
        };

        "element alternate.normal" = {
          background-color = mkLiteral "transparent";
          text-color = mkLiteral "@foreground";
        };

        "element selected.normal" = {
          background-color = mkLiteral "white / 5%";
          text-color = mkLiteral "@foreground";
        };

        element-icon = {
          background-color = mkLiteral "transparent";
          text-color = mkLiteral "inherit";
          size = mkLiteral "64px";
          padding = mkLiteral "10px";
          cursor = mkLiteral "inherit";
        };

        element-text = {
          background-color = mkLiteral "transparent";
          text-color = mkLiteral "inherit";
          highlight = mkLiteral "inherit";
          cursor = mkLiteral "inherit";
          vertical-align = mkLiteral "0.5";
        };

        error-message = {
          padding = mkLiteral "15px";
          border = mkLiteral "2px solid";
          border-radius = mkLiteral "10px";
          border-color = mkLiteral "@selected";
          background-color = mkLiteral "black / 10%";
          text-color = mkLiteral "@foreground";
        };

        textbox = {
          background-color = mkLiteral "red";
          text-color = mkLiteral "@foreground";
          vertical-align = mkLiteral "0.5";
          horizontal-align = mkLiteral "0.0";
          highlight = mkLiteral "none";
        };
      };
    };

  };
}
