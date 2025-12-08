# For motivation, see:
# https://nixos-and-flakes.thiscute.world/best-practices/accelerating-dotfiles-debugging
{ config, lib, ... }:
{
  options = {
    dotFilesDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/Projects/dots";
      description = "The directory where dotfiles are stored in the repository.";
    };
  };
}
