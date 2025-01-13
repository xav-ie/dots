_: {
  config = {
    # https://direnv.net/
    programs.direnv = {
      enable = true;
      # very important, allows caching of build-time deps
      # https://github.com/nix-community/nix-direnv
      nix-direnv.enable = true;
    };
  };
}
