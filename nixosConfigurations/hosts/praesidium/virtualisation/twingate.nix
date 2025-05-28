{ config, ... }:
let
  sharedContainerOpts = {
    autoStart = true;
    image = "twingate/connector:1";
    extraOptions = [ "--network=host" ];
  };
  connector_1 = "twingate-jumping-puffin";
  connector_2 = "twingate-dashing-chicken";
in
{
  config = {
    sops.secrets = {
      "twingate/connector_1" = {
        restartUnits = [ "podman-${connector_1}.service" ];
      };
      "twingate/connector_2" = {
        restartUnits = [ "podman-${connector_2}.service" ];
      };
    };

    virtualisation.oci-containers.containers = {
      ${connector_1} = sharedContainerOpts // {
        environmentFiles = [ config.sops.secrets."twingate/connector_1".path ];
      };
      ${connector_2} = sharedContainerOpts // {
        environmentFiles = [ config.sops.secrets."twingate/connector_2".path ];
      };
    };
  };
}
