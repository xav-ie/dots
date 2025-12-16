{ config, pkgs, ... }:
{
  config = {
    environment = {
      # Changing this does not immediately update all shells.
      variables.SOPS_AGE_KEY_FILE = config.sops.age.keyFile;
      systemPackages = [ pkgs.sops ];
    };

    # Preserve SOPS_AGE_KEY_FILE when using sudo
    security.sudo.extraConfig = ''
      Defaults env_keep += "SOPS_AGE_KEY_FILE"
    '';

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

      secrets."git/allowed_signers" = {
        owner = config.defaultUser;
        mode = "0444";
      };

      # Slack MCP Server tokens (stealth mode)
      secrets."slack/xoxc_token" = {
        owner = config.defaultUser;
        mode = "0400";
      };
      secrets."slack/xoxd_token" = {
        owner = config.defaultUser;
        mode = "0400";
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
