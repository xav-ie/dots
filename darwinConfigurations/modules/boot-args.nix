{ lib, pkgs, ... }:
let
  checkBootArgs = pkgs.writeNuApplication {
    name = "checkBootArgs";
    runtimeInputs = [ pkgs.coreutils ];
    text = # nu
      ''
        def main [] {
          let new_boot_args = (nvram boot-args | complete | get stdout
                              | str substring ("boot-args" | str length)..
                              | str trim)
          let current_boot_args = (sysctl -n kern.bootargs)

          if $new_boot_args != $current_boot_args {
            [
              (ansi yellow_bold)
              "Restart your computer to apply the new boot args."
              (ansi reset)
              (ansi yellow) "\ncurrent_boot_args: " (ansi reset)
              (ansi green) $current_boot_args (ansi reset)
              (ansi yellow) "\nnew_boot_args:     " (ansi reset)
              (ansi green) $new_boot_args (ansi reset)
            ] | str join "" | print -e $in
          }
        }
      '';
  };
in
{
  options = {
    boot-args = {
      checkBootArgs = lib.mkOption {
        type = lib.types.package;
        default = checkBootArgs;
        description = "Script to check if boot args need a restart";
      };
    };
  };

  config = {
    system.nvram.variables = {
      # Allows compiling of arm64e binaries, which is necessary for os-level
      # programs
      "boot-args" = "-arm64e_preview_abi amfi_get_out_of_my_way=1";
    };
  };
}
