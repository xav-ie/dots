{ ... }:
let
  spdfFolder = "/media/spdf";
in
{
  virtualisation.oci-containers.containers.spdf = {
    autoStart = true;
    # https://github.com/Stirling-Tools/Stirling-PDF/releases
    image = "ghcr.io/stirling-tools/stirling-pdf:0.46.1-fat";
    environment = {
      PUID = "1000";
      PGID = "100";
      UMASK = "022";
      SECURITY_ENABLE_LOGIN = "false";
      SECURITY_CSRF_DISABLED = "false";
      SYSTEM_DEFAULT_LOCALE = "en-US";
      METRICS_ENABLED = "false";
    };
    ports = [ "8071:8080" ];
    volumes = [ "${spdfFolder}:/configs" ];
  };

  systemd.tmpfiles.rules = [
    "d ${spdfFolder} 0755 100 1000 -"
  ];
}
