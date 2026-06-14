{
  flake.modules.homeManager.common =
    {
      config,
      lib,
      ...
    }:
    let
      cfg = config.programs.pi;

      settingsJson =
        (
          {
            inherit (cfg)
              defaultProvider
              defaultModel
              defaultThinkingLevel
              lastChangelogVersion
              ;
          }
          // lib.optionalAttrs (cfg.extensions != [ ]) {
            extensions = cfg.extensions |> map (pkg: "${pkg}");
          }
          // lib.optionalAttrs (cfg.extraSettings != { }) cfg.extraSettings
        )
        |> builtins.toJSON;
    in
    {
      options.programs.pi = {
        enable = lib.mkEnableOption "pi coding agent";

        defaultProvider = lib.mkOption {
          type = lib.types.str;
          default = "openrouter";
          description = "Default LLM provider";
        };

        defaultModel = lib.mkOption {
          type = lib.types.str;
          default = "anthropic/claude-3.7-sonnet";
          description = "Default model ID";
        };

        defaultThinkingLevel = lib.mkOption {
          type = lib.types.str;
          default = "medium";
          description = "Default thinking level (off, minimal, low, medium, high, xhigh)";
        };

        lastChangelogVersion = lib.mkOption {
          type = lib.types.str;
          default = "0.66.1";
          description = "Last seen changelog version (prevents changelog popup on launch)";
        };

        extensions = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = [ ];
          description = "Pi extension packages to load";
        };

        extraSettings = lib.mkOption {
          type = lib.types.attrs;
          default = { };
          description = "Additional settings to merge into settings.json";
        };
      };

      config = lib.mkIf cfg.enable {
        home.file.".pi/agent/settings.json".text = settingsJson;
      };
    };
}
