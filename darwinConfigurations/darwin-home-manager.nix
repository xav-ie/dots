{
  config,
  inputs,
  toplevel,
  ...
}:
{
  imports = [
    inputs.home-manager.darwinModules.home-manager
  ];

  home-manager = {
    extraSpecialArgs = {
      inherit inputs toplevel;
    };
    useGlobalPkgs = true;
    useUserPackages = true;
    users."${config.defaultUser}".imports = [
      ../home-manager
      ../home-manager/darwin
    ];
  };
}
