# managed-settings.json plus the context-mode plugin's MCP allowlist entry. A
# plugin server can only be allowlisted by its exact command (names may not
# contain the ":" in "plugin:context-mode:context-mode"), and that command embeds
# the installed plugin version, so derive it from the pinned marketplace input.
{
  homeDirectory,
  inputs,
  pkgs,
}:
let
  src = inputs.claude-marketplace-context-mode;
  inherit (builtins.fromJSON (builtins.readFile "${src}/.claude-plugin/plugin.json")) version;
  base = builtins.fromJSON (builtins.readFile ./managed-settings.json);
in
pkgs.writeText "managed-settings.json" (
  builtins.toJSON (
    base
    // {
      allowedMcpServers = base.allowedMcpServers ++ [
        {
          serverCommand = [
            "node"
            "${homeDirectory}/.claude/plugins/cache/context-mode/context-mode/${version}/start.mjs"
          ];
        }
      ];
    }
  )
)
