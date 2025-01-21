{
  inputs,
  user,
  ...
}:
{
  imports = [
    inputs.home-manager.nixosModules.home-manager
  ];

  home-manager = {
    # backupFileExtension = "backup";
    extraSpecialArgs = {
      inherit inputs;
    };
    useGlobalPkgs = true;
    useUserPackages = true;
    users."${user}".imports = [
      ../home-manager
      ../home-manager/linux
    ];
  };
}
