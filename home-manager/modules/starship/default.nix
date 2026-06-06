_: {
  config = {
    programs.starship = {
      enable = true;
      enableNushellIntegration = false;
      settings = {
        "$schema" = "https://starship.rs/config-schema.json";
        add_newline = true;
        # Explicit module list — `$all` triggers ~20 language probes (Cargo.toml,
        # package.json, Dockerfile, kube/aws/gcp/terraform context, ...) on every
        # prompt that we never use.
        format = "$username$directory$git_branch$git_status$nix_shell$cmd_duration$line_break$character\n";
        aws.disabled = true;
        gcloud.disabled = true;
        git_status.ignore_submodules = true;
        fill.symbol = "-";
        line_break.enabled = true;
        character = {
          format = "$symbol";
          # default
          # success_symbol = "[❯](bold green)";
          # error_symbol = "[❯](bold red)";

          # Does not work, it will not print the new line
          # I believe that *some* character is required
          # success_symbol = "[](bold green)";
          # error_symbol = "[](bold red)";

          # ...so we print a zero-width space!
          # success_symbol = "​";
          # error_symbol = "​";
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
          success_symbol = "";
          error_symbol = "";

        };
        nix_shell = {
          format = "via [ $name](bold blue) ";
          impure_msg = "";
        };
      };
    };
  };
}
