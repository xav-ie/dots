{ config, lib, ... }:
let
  cfg = config.programs.bat;
  # Use bat package store path as cache key - only rebuild when bat updates
  cacheKey = builtins.hashString "sha256" (toString cfg.package);
in
{
  config = {
    programs.bat = {
      enable = true;
      config = {
        theme = "ansi";
        paging = "always";
        style = "plain";
        wrap = "never";
      };
    };

    # Override batCache to skip if bat package hasn't changed
    home.activation.batCache = lib.mkForce (
      lib.hm.dag.entryAfter [ "linkGeneration" ] ''
        cache_dir="${config.xdg.cacheHome}/bat"
        hash_file="$cache_dir/.nix-cache-key"
        current_hash="${cacheKey}"

        stored_hash=""
        [[ -f "$hash_file" ]] && stored_hash=$(cat "$hash_file")

        if [[ "$current_hash" != "$stored_hash" ]]; then
          run ${lib.getExe cfg.package} cache --build
          mkdir -p "$cache_dir"
          echo "$current_hash" > "$hash_file"
        fi
      ''
    );

    home.sessionVariables = lib.mkIf cfg.enable {
      PAGER = lib.getExe cfg.package;
    };
  };
}
