{
  inputs,
  outputs,
  user,
  ...
}:
{
  home-manager = {
    extraSpecialArgs = {
      inherit inputs outputs;
    };
    useGlobalPkgs = true;
    useUserPackages = true;
    users."${user}".imports = [
      ./modules/home-manager
      ./modules/home-manager/linux
    ];
  };
}
