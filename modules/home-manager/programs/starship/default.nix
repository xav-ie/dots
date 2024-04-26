{ ... }:
{
  programs = {
    starship = {
      enable = true;
      settings = {
        "$schema" = "https://starship.rs/config-schema.json";
        add_newline = false;
        "aws" = {
          disabled = true;
        };
        "gcloud" = {
          disabled = true;
        };
      };
    };
  };
}
