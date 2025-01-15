_: {
  imports = [
    ./module.nix
  ];

  config = {
    programs.ov = {
      enable = true;
      settings = {
        QuitSmall = true;
        StyleSectionLine = {
          Background = "#200030";
        };
        # TODO: add keybind deduplicaiton checks
        KeyBind = {
          bottom = [
            "End"
            "G"
          ];
          delimiter = [ "D" ];
          down = [
            "Enter"
            "Down"
            "ctrl+N"
            "j"
          ];
          goto = [ "L" ];
          jump_target = [ "J" ];
          line_number_mode = [ "l" ];
          next_section = [
            "space"
            "}"
          ];
          page_half_down = [
            "ctrl+d"
            "d"
          ];
          page_half_up = [
            "ctrl+u"
            "u"
          ];
          previous_section = [
            "^"
            "{"
          ];
          skip_lines = [ "s" ];
          save_buffer = [ "ctrl+s" ];
          top = [
            "Home"
            "g"
          ];
          up = [
            "Up"
            "ctrl+p"
            "k"
          ];
          set_write_exit = [ "ctrl+q" ];
        };

      };
    };
  };
}
