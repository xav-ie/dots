{
  flake.modules.nixos.linux = _: {
    config.nixpkgs.config.allowUnfree = true;
  };
}
