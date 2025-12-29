{ config, lib, pkgs, ... }:
let
  certDir = "${config.home.homeDirectory}/.config/wayvnc";
in
{
  # Generate self-signed certs if they don't exist
  home.activation.wayvncCerts = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    CERT_DIR="${certDir}"
    if [ ! -f "$CERT_DIR/rsa_key.pem" ]; then
      mkdir -p "$CERT_DIR"
      ${pkgs.openssl}/bin/openssl genrsa -traditional -out "$CERT_DIR/rsa_key.pem" 4096
      ${pkgs.openssl}/bin/openssl genrsa -traditional -out "$CERT_DIR/tls_key.pem" 2048
      ${pkgs.openssl}/bin/openssl req -new -x509 -key "$CERT_DIR/tls_key.pem" \
        -out "$CERT_DIR/tls_cert.pem" -days 3650 -subj "/CN=wayvnc"
      chmod 600 "$CERT_DIR"/*.pem
    fi
  '';

  services.wayvnc = {
    enable = true;
    autoStart = true;
    settings = {
      address = "127.0.0.1";
      port = 5900;
      enable_auth = true;
      username = "x";
      password = "vnc";
      rsa_private_key_file = "${certDir}/rsa_key.pem";
      private_key_file = "${certDir}/tls_key.pem";
      certificate_file = "${certDir}/tls_cert.pem";
      relax_encryption = true;
    };
  };
}
