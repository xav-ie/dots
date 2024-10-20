{ pkgs, ... }:
{
  config = {
    # heavily borrowed from https://www.youtube.com/watch?v=z8y_qRUYEWU
    programs.lf = {
      enable = true;
      commands = {
        dragon-out = ''%${pkgs.xdragon}/bin/xdragon -a -x "$fx"'';
        editor-open = "$$EDITOR $f";
        mkdir = # sh
          ''
            ''${{
              printf "Directory Name: "
              read DIR
              mkdir $DIR
            }}'';
      };
      keybindings = {
        # ?
        "\\\"" = "";
        o = "open";
        c = "mkdir";
        "." = "set hidden!";
        "`" = "mark-load";
        "\\'" = "mark-load";
        "<enter>" = "editor-open";
        do = "dragon-out";
        "g~" = "cd";
        gh = "cd";
        "g/" = "/";
        ee = "editor-open";
        V = ''''$${pkgs.bat}/bin/bat --paging always "$f"'';
      };
      settings = {
        autochafa = true;
        chafasixel = true;
        sixel = true;
        preview = true;
        hidden = true;
        drawbox = true;
        icons = true;
        ignorecase = true;

        previewer = "${pkgs.ctpv}/bin/ctpv";
        cleaner = "${pkgs.ctpv}/bin/ctpvclear";
      };
    };
    home.file.".config/lf/icons".source = ./icons;
  };
}
