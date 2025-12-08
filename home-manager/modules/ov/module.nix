{
  pkgs,
  config,
  lib,
  ...
}:
let
  cfg = config.programs.ov;
  yamlFormat = pkgs.formats.yaml { };
  defaultSettings = {
    General = {
      AlternateRows = false;
      ColumnDelimiter = ",";
      ColumnMode = false;
      Header = 0;
      LineNumMode = false;
      MarkStyleWidth = 1;
      TabWidth = 8;
      WrapMode = true;
    };
    KeyBind = {
      alter_rows_mode = [ "C" ];
      backsearch = [ "?" ];
      bottom = [ "End" ];
      cancel = [ "ctrl+c" ];
      column_mode = [ "c" ];
      delimiter = [ "d" ];
      down = [
        "Enter"
        "Down"
        "ctrl+N"
      ];
      exit = [
        "Escape"
        "q"
      ];
      follow_all = [ "ctrl+a" ];
      follow_mode = [ "ctrl+f" ];
      follow_section = [ "F2" ];
      goto = [ "g" ];
      half_left = [ "ctrl+left" ];
      half_right = [ "ctrl+right" ];
      header = [ "H" ];
      help = [
        "h"
        "ctrl+alt+c"
        "ctrl+f1"
      ];
      hide_other = [ "alt+-" ];
      jump_target = [ "j" ];
      last_section = [ "9" ];
      left = [ "left" ];
      line_number_mode = [ "G" ];
      logdoc = [ "ctrl+f2" ];
      mark = [ "m" ];
      multi_color = [ "." ];
      next_backsearch = [ "N" ];
      next_doc = [ "]" ];
      next_mark = [ ">" ];
      next_search = [ "n" ];
      next_section = [ "space" ];
      page_down = [
        "PageDown"
        "ctrl+v"
      ];
      page_half_down = [ "ctrl+d" ];
      page_half_up = [ "ctrl+u" ];
      page_up = [
        "PageUp"
        "ctrl+b"
      ];
      previous_doc = [ "[" ];
      previous_mark = [ "<" ];
      previous_section = [ "^" ];
      reload = [
        "ctrl+alt+l"
        "F5"
      ];
      remove_all_mark = [ "ctrl+delete" ];
      remove_mark = [ "M" ];
      right = [ "right" ];
      search = [ "/" ];
      section_delimiter = [ "alt+d" ];
      section_header_num = [ "F7" ];
      section_start = [
        "ctrl+F3"
        "alt+s"
      ];
      set_view_mode = [
        "p"
        "P"
      ];
      set_write_exit = [ "ctrl+1" ];
      skip_lines = [ "ctrl+s" ];
      suspend = [ "ctrl+z" ];
      sync = [ "ctrl+l" ];
      tabwidth = [ "t" ];
      toggle_mouse = [
        "ctrl+f3"
        "ctrl+alt+r"
      ];
      top = [ "Home" ];
      up = [
        "Up"
        "ctrl+p"
      ];
      watch = [
        "ctrl+alt+w"
        "F4"
      ];
      watch_interval = [ "ctrl+w" ];
      wrap_mode = [
        "w"
        "W"
      ];
      write_exit = [ "Q" ];
    };
    Mode = {
      markdown = {
        SectionDelimiter = "^#";
        WrapMode = true;
      };
      mysql = {
        AlternateRows = true;
        ColumnDelimiter = "|";
        ColumnMode = true;
        Header = 3;
        LineNumMode = false;
        WrapMode = true;
      };
      psql = {
        AlternateRows = true;
        ColumnDelimiter = "|";
        ColumnMode = true;
        Header = 2;
        LineNumMode = false;
        WrapMode = true;
      };
    };
    Prompt = {
      Normal = null;
    };
    StyleAlternate = {
      Background = "gray";
    };
    StyleColumnHighlight = {
      reverse = true;
    };
    StyleHeader = {
      Bold = true;
    };
    StyleJumpTargetLine = {
      Underline = true;
    };
    StyleLineNumber = {
      Bold = true;
    };
    StyleMarkLine = {
      Background = "darkgoldenrod";
    };
    StyleMultiColorHighlight = [
      { Foreground = "red"; }
      { Foreground = "aqua"; }
      { Foreground = "yellow"; }
      { Foreground = "fuchsia"; }
      { Foreground = "lime"; }
      { Foreground = "blue"; }
      { Foreground = "grey"; }
    ];
    StyleOverLine = {
      Underline = true;
    };
    StyleOverStrike = {
      Bold = true;
    };
    StyleSearchHighlight = {
      Reverse = true;
    };
    StyleSectionLine = {
      Background = "slateblue";
    };
  };

  finalSettings = lib.recursiveUpdate defaultSettings cfg.settings;
in
{
  options.programs.ov = {
    enable = lib.mkEnableOption "ov";
    package = lib.mkPackageOption pkgs "ov" { };
    enableBatIntegration = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether to enable ov's git-bat integration.

        If enabled, ...
      '';
    };
    # enableBatGitIntegration = lib.mkEnableOption "enable bat git integration" // lib.mkDefault true;

    settings = lib.mkOption {
      inherit (yamlFormat) type;
      # TODO: consolidate
      default = defaultSettings;
      example = # nix
        ''
          {
            General = {
              AlternateRows = false;
              ColumnDelimiter = ",";
              ColumnMode = false;
              Header = 0;
              LineNumMode = false;
              MarkStyleWidth = 1;
              TabWidth = 8;
              WrapMode = true;
            };
            KeyBind = {
              alter_rows_mode = [ "C" ];
              backsearch = [ "?" ];
              bottom = [ "End" ];
              cancel = [ "ctrl+c" ];
              column_mode = [ "c" ];
              delimiter = [ "d" ];
              down = [
                "Enter"
                "Down"
                "ctrl+N"
              ];
              exit = [
                "Escape"
                "q"
              ];
              follow_all = [ "ctrl+a" ];
              follow_mode = [ "ctrl+f" ];
              follow_section = [ "F2" ];
              goto = [ "g" ];
              half_left = [ "ctrl+left" ];
              half_right = [ "ctrl+right" ];
              header = [ "H" ];
              help = [
                "h"
                "ctrl+alt+c"
                "ctrl+f1"
              ];
              hide_other = [ "alt+-" ];
              jump_target = [ "j" ];
              last_section = [ "9" ];
              left = [ "left" ];
              line_number_mode = [ "G" ];
              logdoc = [ "ctrl+f2" ];
              mark = [ "m" ];
              multi_color = [ "." ];
              next_backsearch = [ "N" ];
              next_doc = [ "]" ];
              next_mark = [ ">" ];
              next_search = [ "n" ];
              next_section = [ "space" ];
              page_down = [
                "PageDown"
                "ctrl+v"
              ];
              page_half_down = [ "ctrl+d" ];
              page_half_up = [ "ctrl+u" ];
              page_up = [
                "PageUp"
                "ctrl+b"
              ];
              previous_doc = [ "[" ];
              previous_mark = [ "<" ];
              previous_section = [ "^" ];
              reload = [
                "ctrl+alt+l"
                "F5"
              ];
              remove_all_mark = [ "ctrl+delete" ];
              remove_mark = [ "M" ];
              right = [ "right" ];
              search = [ "/" ];
              section_delimiter = [ "alt+d" ];
              section_header_num = [ "F7" ];
              section_start = [
                "ctrl+F3"
                "alt+s"
              ];
              set_view_mode = [
                "p"
                "P"
              ];
              set_write_exit = [ "ctrl+1" ];
              skip_lines = [ "ctrl+s" ];
              suspend = [ "ctrl+z" ];
              sync = [ "ctrl+l" ];
              tabwidth = [ "t" ];
              toggle_mouse = [
                "ctrl+f3"
                "ctrl+alt+r"
              ];
              top = [ "Home" ];
              up = [
                "Up"
                "ctrl+p"
              ];
              watch = [
                "ctrl+alt+w"
                "F4"
              ];
              watch_interval = [ "ctrl+w" ];
              wrap_mode = [
                "w"
                "W"
              ];
              write_exit = [ "Q" ];
            };
            Mode = {
              markdown = {
                SectionDelimiter = "^#";
                WrapMode = true;
              };
              mysql = {
                AlternateRows = true;
                ColumnDelimiter = "|";
                ColumnMode = true;
                Header = 3;
                LineNumMode = false;
                WrapMode = true;
              };
              psql = {
                AlternateRows = true;
                ColumnDelimiter = "|";
                ColumnMode = true;
                Header = 2;
                LineNumMode = false;
                WrapMode = true;
              };
            };
            Prompt = {
              Normal = null;
            };
            StyleAlternate = {
              Background = "gray";
            };
            StyleColumnHighlight = {
              reverse = true;
            };
            StyleHeader = {
              Bold = true;
            };
            StyleJumpTargetLine = {
              Underline = true;
            };
            StyleLineNumber = {
              Bold = true;
            };
            StyleMarkLine = {
              Background = "darkgoldenrod";
            };
            StyleMultiColorHighlight = [
              { Foreground = "red"; }
              { Foreground = "aqua"; }
              { Foreground = "yellow"; }
              { Foreground = "fuchsia"; }
              { Foreground = "lime"; }
              { Foreground = "blue"; }
              { Foreground = "grey"; }
            ];
            StyleOverLine = {
              Underline = true;
            };
            StyleOverStrike = {
              Bold = true;
            };
            StyleSearchHighlight = {
              Reverse = true;
            };
            StyleSectionLine = {
              Background = "slateblue";
            };
          } 
        '';
      description = ''
        Configuration written to
        {file}`$XDG_CONFIG_HOME/config.yaml`.

        See <https://github.com/noborus/ov> for the full list
        of options.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];

    xdg.configFile."ov/config.yaml" = lib.mkIf (finalSettings != { }) {
      source = yamlFormat.generate "ov-config" finalSettings;
    };

    programs.bat = lib.mkIf cfg.enableBatIntegration {
      config = {
        pager = "ov --header 3";
      };
    };

    home.sessionVariables = lib.mkIf cfg.enableBatIntegration {
      BAT_PAGER = config.programs.bat.config.pager or "";
    };

    programs.git = lib.mkIf cfg.enableBatIntegration {
      iniContent.core.pager = lib.mkForce "delta --pager='ov'";

      extraConfig = {
        pager = {
          # TODO: fix
          blame = "delta";
          diff = "delta --features ov-diff";
          log = "delta --features ov-log";
          reflog = "delta";
          show = "delta --features ov-show";
        };
      };

      delta.options =
        let
          # greedily matches
          subjects = [
            "chore"
            "docs"
            "feat"
            "fix"
            "refactor"
            "[a-z]+"
          ];
          suffix = ''\(.+\)'';
          commitMessages = builtins.concatStringsSep "," (map (subject: "${subject}${suffix}") subjects);
          multiColorHighlights = builtins.concatStringsSep "," [
            commitMessages
            "Merge pull request .+"
            "https?://.+"
          ];
          delimiters = builtins.concatStringsSep "|" [
            "commit"
            "added:"
            "removed:"
            "renamed:"
            "Δ"
          ];
          ov-show-and-diff-pager = "ov --section-delimiter '^(${delimiters})' --section-header --pattern '•' -M '${multiColorHighlights}'";
        in
        {
          "ov-show" = {
            pager = ov-show-and-diff-pager;
          };
          "ov-diff" = {
            pager = ov-show-and-diff-pager;
          };
          "ov-log" = {
            pager = "ov --section-delimiter '^commit' --section-header-num 3 --section-header --pattern 'commit' -M '${multiColorHighlights}'";
          };
        };

    };

  };
}
