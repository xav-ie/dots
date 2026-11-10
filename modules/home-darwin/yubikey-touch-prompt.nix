# Shows "Touch your YubiKey" while the key waits for a touch, e.g. for sudo on
# praesidium over the forwarded agent. See packages/yubikey-touch-prompt.
{
  flake.modules.homeManager.darwin =
    { pkgs, lib, ... }:
    {
      launchd.agents.yubikey-touch-prompt = {
        enable = true;
        config = {
          Program = lib.getExe pkgs.pkgs-mine.yubikey-touch-prompt;
          KeepAlive = true;
          RunAtLoad = true;
          ProcessType = "Interactive";
          StandardErrorPath = "/tmp/yubikey-touch-prompt.err";
        };
      };
    };
}
