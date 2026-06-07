{
  flake.modules.darwin.macos = _: {
    config = {
      services.mkcert-ca.enable = false;
      services.reverse-proxy.enable = false;
    };
  };
}
