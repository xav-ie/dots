{
  flake.modules.homeManager.linux = _: {
    config = {
      services.cliphist = {
        enable = true;
      };
    };
  };
}
