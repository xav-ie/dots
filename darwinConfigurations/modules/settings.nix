{ ... }:
{
  config = {
    services.mkcert-ca.enable = true;
    services.reverse-proxy.enable = true;
  };
}
