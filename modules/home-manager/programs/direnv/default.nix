{ ... }:
{
  programs.direnv = {
    enable = true;
    # very important, allows caching of build-time deps
    nix-direnv.enable = true;
  };
}
