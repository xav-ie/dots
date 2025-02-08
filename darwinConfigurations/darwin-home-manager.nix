{
  inputs,
  user,
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
    users."${user}".imports = [
      ../home-manager
      ../home-manager/darwin
    ];
  };
}
