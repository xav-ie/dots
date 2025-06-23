{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.mkcert-ca;

  mkcertCAHelper = pkgs.writeNuApplication {
    name = "mkcert-ca-helper";
    runtimeInputs = with pkgs; [
      mkcert
      nssTools
    ];
    text = # nu
      ''
        def main [out: string] {
          $env.CAROOT = $out
          mkdir $out
          mkcert -install out+err>| ignore
          mkcert -CAROOT
        }
      '';
  };

  mkcertCA =
    pkgs.runCommand "mkcertCA"
      {
        buildInputs = [
          mkcertCAHelper
          pkgs.coreutils
        ];
      }
      ''
        cp -r ${mkcertCAHelper} $out
        chmod -R +w $out
        patchShebangs $out/bin/
        $out/bin/mkcert-ca-helper $out
      '';
in
{
  options.services.mkcert-ca = {
    enable = lib.mkEnableOption "mkcert CA and certificate generation";
  };

  config = lib.mkIf cfg.enable {
    environment.variables = {
      NODE_EXTRA_CA_CERTS = "${mkcertCA}/rootCA.pem";
    };

    launchd.daemons.mkcert-ca-trust = {
      serviceConfig = {
        ProgramArguments = [
          "/bin/sh"
          "-c"
          # sh
          ''
            # Remove any existing mkcert CAs first
            security find-certificate -c "mkcert" -a -Z /Library/Keychains/System.keychain | \
              grep "SHA-1 hash" | \
              awk '{print $3}' | \
              xargs -I {} security delete-certificate -Z {} /Library/Keychains/System.keychain 2>/dev/null || true

            # Add the new CA
            security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ${mkcertCA}/rootCA.pem
          ''
        ];
        RunAtLoad = true;
        KeepAlive = false;
      };
    };

    launchd.daemons.generate-certs = {
      serviceConfig = {
        ProgramArguments = [
          "/bin/sh"
          "-c"
          # sh
          ''
            PROXY_DOMAIN=$(cat ${config.sops.secrets."reverse-proxy/reverse-hostname".path})
            mkdir -p /var/lib/certs
            export CAROOT=${mkcertCA}
            ${lib.getExe pkgs.mkcert} -cert-file /var/lib/certs/cert.pem \
              -key-file /var/lib/certs/key.pem \
              "$PROXY_DOMAIN"
            chmod 644 /var/lib/certs/cert.pem
            chmod 600 /var/lib/certs/key.pem
          ''
        ];
        RunAtLoad = true;
        KeepAlive = false;
      };
    };

    # Cleanup when disabled
    # TODO: is there a better way?
    system.activationScripts.postActivation.text = lib.mkIf (!cfg.enable) ''
      echo "Removing mkcert CA from system keychain..."
      security find-certificate -c "mkcert" -a -Z /Library/Keychains/System.keychain | \
        grep "SHA-1 hash" | \
        awk '{print $3}' | \
        xargs -I {} security delete-certificate -Z {} /Library/Keychains/System.keychain 2>/dev/null || true
    '';
  };
}
