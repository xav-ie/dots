_: {
  config = {
    programs.starship = {
      enable = true;
      settings = {
        "$schema" = "https://starship.rs/config-schema.json";
        add_newline = false;
        format = "$all";
        aws.disabled = true;
        gcloud.disabled = true;
        fill.symbol = "-";
        line_break.enabled = true;
        character = {
          format = "$symbol";
          # default
          # success_symbol = "[❯](bold green)";
          # error_symbol = "[❯](bold red)";

          # Does not work, it will not print the new line
          # I belive that *some* character is required
          # success_symbol = "[](bold green)";
          # error_symbol = "[](bold red)";

          # ...so we print a zero-width space!
          success_symbol = "​";
          error_symbol = "​";
          # Alternate zero-width characters for testing:
          # Zero Width Non-Joiner (U+200C)
          # success_symbol = "‌";
          # error_symbol = "‌";
          # Zero Width Joiner (U+200D)
          # success_symbol = "‍";
          # error_symbol = "‍";
          # Word Joiner (U+2060)
          # success_symbol = "⁠";
          # error_symbol = "⁠";

        };
      };
    };
  };
}
