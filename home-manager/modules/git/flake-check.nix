# Flake-parts module for git config validation
# Runs checks via `nix flake check` without affecting system builds
toplevel:
{ lib, ... }:
let
  # Map system types to their flake configuration attrsets
  systemConfigs = {
    darwin = toplevel.config.flake.darwinConfigurations;
    linux = toplevel.config.flake.nixosConfigurations;
  };

  # Extract the OS type from a system string (e.g., "aarch64-darwin" -> "darwin")
  getOsType =
    system:
    if lib.hasSuffix "-darwin" system then
      "darwin"
    else if lib.hasSuffix "-linux" system then
      "linux"
    else
      null;

  # Run both checks on git settings, return combined result
  checkGitSettings =
    gitSettings:
    let
      canonical = import ./canonical-case-check.nix {
        inherit lib gitSettings;
      };
      collision = import ./case-collision-check.nix {
        inherit lib gitSettings;
      };
    in
    {
      hasErrors = canonical.hasErrors || collision.hasErrors;
      errorMessage = lib.concatStringsSep "\n" (
        lib.filter (s: s != "") [
          canonical.errorMessage
          collision.errorMessage
        ]
      );
    };
in
{
  perSystem =
    { pkgs, system, ... }:
    let
      osType = getOsType system;
      configs = systemConfigs.${osType} or { };

      # Check all hosts for this system type
      # Each host may have different git settings due to overrides
      hostChecks = lib.mapAttrs (
        hostName: hostConfig:
        let
          # Get home-manager user configs for this host
          hmUsers = hostConfig.config.home-manager.users or { };
          # Check each user's git settings
          userChecks = lib.mapAttrs (
            _userName: userConfig:
            let
              gitSettings = userConfig.programs.git.settings or { };
            in
            checkGitSettings gitSettings
          ) hmUsers;
          # Collect errors from all users
          usersWithErrors = lib.filterAttrs (_: check: check.hasErrors) userChecks;
        in
        {
          hasErrors = usersWithErrors != { };
          errorMessages = lib.mapAttrsToList (
            userName: check: "  ${hostName} (${userName}):\n${check.errorMessage}"
          ) usersWithErrors;
        }
      ) configs;

      hostsWithErrors = lib.filterAttrs (_: h: h.hasErrors) hostChecks;
      hasAnyErrors = hostsWithErrors != { };
      allErrorMessages = lib.concatLists (lib.mapAttrsToList (_: h: h.errorMessages) hostsWithErrors);
    in
    {
      checks = lib.optionalAttrs (osType != null && configs != { }) {
        git-config = pkgs.runCommand "git-config-check" { } (
          if hasAnyErrors then
            ''
              echo "Git config validation failed:"
              echo ""
              ${lib.concatMapStringsSep "\n" (msg: ''echo "${msg}"'') allErrorMessages}
              exit 1
            ''
          else
            ''
              touch $out
            ''
        );
      };
    };
}
