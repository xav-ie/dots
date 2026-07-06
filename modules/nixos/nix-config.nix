{
  flake.modules.nixos.base = _: {
    config.nixpkgs.config.allowUnfree = true;
  };
}
