{
  config,
  lib,
  ...
}:
let
  # Hash the parts the activation script uses, including user/group properties it modifies
  usersConfigHash = builtins.hashString "sha256" (
    builtins.toJSON {
      inherit (config.users)
        knownUsers
        knownGroups
        uids
        gids
        ;
      userConfigs = lib.mapAttrs (_n: u: {
        inherit (u)
          gid
          description
          shell
          home
          isHidden
          createHome
          ;
      }) config.users.users;
      groupConfigs = lib.mapAttrs (_n: g: {
        inherit (g) gid description members;
      }) config.users.groups;
    }
  );
in
{
  options.system.usersOptimization.enable = lib.mkEnableOption "skip user setup when unchanged" // {
    default = true;
  };

  config = lib.mkIf config.system.usersOptimization.enable {
    # Wrap the original users script in a function, then conditionally call it
    system.activationScripts.users.text = lib.mkMerge [
      # Open the function wrapper (runs before original script)
      (lib.mkBefore ''
        _nix_darwin_setup_users() {
      '')
      # Close the function and conditionally execute (runs after original script)
      (lib.mkAfter ''
        }
        hash_file="/var/lib/nix-darwin/users-config.hash"
        current_hash="${usersConfigHash}"
        stored_hash=$(cat "$hash_file" 2>/dev/null) || stored_hash=""
        if [ "$current_hash" != "$stored_hash" ]; then
          _nix_darwin_setup_users
          mkdir -p "$(dirname "$hash_file")"
          echo "$current_hash" > "$hash_file"
        else
          echo "users config unchanged, skipping..." >&2
        fi
      '')
    ];
  };
}
