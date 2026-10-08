{
  flake.modules.nixos.linux =
    { config, ... }:
    {
      # With linger, logind starts the user manager at boot, outside the
      # systemd-user-sessions gate home-manager orders itself before. Without
      # this it can load unit files before boot-time activation rewrites them,
      # then keeps the stale definitions (HM skips the reload when no user
      # manager is up yet).
      systemd.services."user@".after = [ "home-manager-${config.defaultUser}.service" ];
    };
}
