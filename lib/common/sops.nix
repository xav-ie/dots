{ config, pkgs, ... }:
{
  config = {
    environment = {
      # TODO: add nu shell env reloading...
      variables.SOPS_AGE_KEY_FILE = config.sops.age.keyFile;
      systemPackages = [ pkgs.sops ];
    };

    sops = {
      defaultSopsFile = ../../secrets/main.yaml;
      # TODO: what does not adding to the cache do?
      # # The quoting prevents this from being added to the cache 🙈
      # defaultSopsFile = "/home/x/Projects/secrets/main.yaml";
      # # It is okay for this to not be in the store..., although I can't find
      # # the consequences of doing this
      # validateSopsFiles = !builtins.isString config.sops.defaultSopsFile;
      age = {
        # Do not auto-derive from ssh key, please.
        generateKey = false;
        keyFile = "/etc/age/keys.txt";
      };
    };

    # Ensure that no one may read my key file
    system.activationScripts.preActivation =
      let
        rootGroup = if pkgs.stdenv.isLinux then "root" else "wheel";
      in
      {
        text = # sh
          ''
            mkdir -p "${builtins.dirOf config.sops.age.keyFile}" || true
            touch ${config.sops.age.keyFile}
            chown -R root:${rootGroup} "${config.sops.age.keyFile}"
            chmod 0640 "${config.sops.age.keyFile}"
          '';
      };
  };
}
