{ inputs, config, ... }:
{
  imports = [
    inputs.quadlet-nix.nixosModules.quadlet
  ];

  options = { };

  config = {
    virtualisation.quadlet =
      let
        inherit (config.virtualisation.quadlet) networks pods;
      in
      {
        containers = {
          nginx.containerConfig.image = "docker.io/library/nginx:latest";
          nginx.containerConfig.networks = [
            "podman"
            networks.internal.ref
          ];
          nginx.containerConfig.pod = pods.foo.ref;
          nginx.serviceConfig.TimeoutStartSec = "60";
        };
        networks = {
          internal.networkConfig.subnets = [ "10.0.123.1/24" ];
        };
        pods = {
          # foo = { };
          foo.podConfig.podmanArgs = [ "--exit-policy=continue" ];
        };
      };
  };
}
