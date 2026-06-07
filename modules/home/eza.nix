{
  flake.modules.homeManager.common = _: {
    config = {
      programs.eza = {
        enable = true;
        git = true;
        icons = "auto";
      };
    };
  };
}
