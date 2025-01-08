{
  inputs,
  user,
  ...
}:
{
  imports = [
    inputs.home-manager.darwinModules.home-manager
  ];

  home-manager = {
    extraSpecialArgs = {
      inherit inputs;
    };
    useGlobalPkgs = true;
    useUserPackages = true;
    users."${user}".imports = [
      ../home-manager
      ../home-manager/darwin
    ];
  };
}
