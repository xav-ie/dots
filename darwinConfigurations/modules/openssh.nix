{ config, lib, ... }:

with lib;

let
  cfg = config.services.openssh;
in
{
  options.services.openssh = {
    settings = mkOption {
      type = types.submodule {
        options = {
          AcceptEnv = mkOption {
            type = types.str;
            default = "";
            description = "Space-separated list of environment variable names to accept from SSH clients.";
            example = "COLORTERM TERM LANG LC_ALL";
          };
        };
      };
      default = { };
      description = "Configuration options for the SSH daemon.";
    };
  };

  config = mkIf (cfg.enable && cfg.settings.AcceptEnv != "") {
    # Write SSH server configuration to accept environment variables
    environment.etc."ssh/sshd_config.d/100-nix-darwin-accept-env.conf".text = ''
      # Managed by nix-darwin
      # Accept environment variables from SSH clients
      AcceptEnv ${cfg.settings.AcceptEnv}
    '';

    # Restart SSH daemon only when configuration actually changes
    # Compare current config with new config to detect changes
    system.activationScripts.postActivation.text =
      let
        configPath = "/etc/ssh/sshd_config.d/100-nix-darwin-accept-env.conf";
        newConfig = # sh
          ''
            # Managed by nix-darwin
            # Accept environment variables from SSH clients
            AcceptEnv ${cfg.settings.AcceptEnv}
          '';
      in
      #sh
      ''
        if [ -f "${configPath}" ]; then
          current_config=$(cat "${configPath}" 2>/dev/null || echo "")
          new_config="${newConfig}"
          if [ "$current_config" != "$new_config" ]; then
            echo "SSH configuration changed, restarting daemon..."
            launchctl kickstart -k system/com.openssh.sshd 2>/dev/null || true
          fi
        else
          # Config file doesn't exist yet, will be created but service might need restart
          echo "SSH configuration created, restarting daemon..."
          launchctl kickstart -k system/com.openssh.sshd 2>/dev/null || true
        fi
      '';
  };
}
