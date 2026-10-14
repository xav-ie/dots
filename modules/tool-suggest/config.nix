# Config for the shared tool-suggest engine (packages/tool-suggest). The
# compiled binary re-reads this file on every invocation, so claude's hooks
# and the opencode plugin shim are both configured by it. Out-of-store
# symlink: threshold tweaks apply on the next hook event, no rebuild.
{
  flake.modules.homeManager.common =
    { config, ... }:
    {
      xdg.configFile."tool-suggest/config.json".source =
        config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/modules/tool-suggest/config.json";
    };
}
