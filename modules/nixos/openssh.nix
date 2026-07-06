{
  flake.modules.nixos.base = {
    config.services.openssh = {
      enable = true;
      settings = {
        # Accept environment variables from SSH clients for proper locale and terminal support
        AcceptEnv = [
          "COLORTERM"
          "LANG"
          "LC_ALL"
          "TERM"
        ];
        # Send connection check every X seconds
        ClientAliveInterval = 30;
        # Terminate connection after X failed connection checks
        ClientAliveCountMax = 3;
      };
    };
  };
}
