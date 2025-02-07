{
  inputs,
  user,
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
    users."${user}".imports = [
      ../home-manager
      ../home-manager/linux
    ];
  };
}
