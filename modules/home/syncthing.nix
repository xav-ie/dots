{
  flake.modules.homeManager.common =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      home = config.home.homeDirectory;

      # syncthing --home="$HOME/Library/Application Support/Syncthing" device-id  # darwin
      # syncthing --home="$HOME/.local/state/syncthing" device-id                 # linux
      deviceIds = {
        nox = "NTG53RG-K4LNPFR-OX3IACD-BOF4AQL-PVNXJA5-C72S5JW-NRSIEOW-PL7HXQK";
        praesidium = "5QRVPW4-SFMRVU4-QGQ6DKS-CRTSATN-43B5PLA-4EHC54I-KIZLKC3-GE5NMA6";
      };

      peer = if pkgs.stdenv.isDarwin then "praesidium" else "nox";

      # An empty ID is rejected by the config API, so declare nothing until both are set.
      paired = deviceIds.nox != "" && deviceIds.praesidium != "";

      versioning = {
        type = "trashcan";
        params.cleanoutDays = "365";
      };
    in
    {
      home.packages = [ config.services.syncthing.package ];

      services.syncthing = {
        enable = true;

        settings = lib.mkIf paired {
          devices.${peer} = {
            id = deviceIds.${peer};
            # Prefer the tailnet; "dynamic" keeps discovery/relays as fallback.
            addresses = [
              "tcp://${peer}.gecko-bonito.ts.net:22000"
              "dynamic"
            ];
          };

          folders."${home}/.claude/projects" = {
            id = "claude-projects";
            devices = [ peer ];
            inherit versioning;
          };
        };
      };

      # Only the $HOME-relative project names (claude-project-name) match
      # across machines. Folders still in Claude's path-encoded "-..." form are
      # from sessions outside $HOME (/tmp etc.) and mean nothing on the peer.
      home.file.".claude/projects/.stignore".text = ''
        /-*
      '';
    };
}
