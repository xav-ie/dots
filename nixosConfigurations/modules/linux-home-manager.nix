{
  inputs,
  config,
  toplevel,
  ...
}:
{
  imports = [
    inputs.home-manager.nixosModules.home-manager
  ];

  home-manager = {
    # backupFileExtension = "backup";
    extraSpecialArgs = {
      flake-partsConfig = config;
      inherit inputs toplevel;
    };
    useGlobalPkgs = true;
    useUserPackages = true;
    users."${config.defaultUser}".imports = [
      ../../home-manager
      ../../home-manager/linux
    ];
  };
}
