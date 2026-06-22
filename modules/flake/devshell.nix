# The `nix develop` shell (also what `direnv` loads).
{ inputs, ... }:
{
  perSystem =
    {
      config,
      lib,
      pkgs,
      system,
      ...
    }:
    let
      # The perSystem `pkgs` carries no overlays and tracks the (intentionally
      # lagging) main nixpkgs pin, so the dev CLIs go stale there. Pull them from
      # nixpkgs-bleeding instead, matching the `pkgs-bleeding` set used elsewhere.
      pkgs-bleeding = import inputs.nixpkgs-bleeding {
        inherit system;
        config.allowUnfree = true;
      };
    in
    {
      devShells.default = pkgs.mkShell {
        packages =
          (with pkgs-bleeding; [
            just
            nix-diff
            nushell
          ])
          ++ (with config.packages; [
            nom-run
            nix-output-monitor
          ])
          ++ lib.optionals pkgs.stdenv.isLinux (
            with pkgs-bleeding;
            [
              nh
              nixos-rebuild
            ]
          )
          ++ lib.optionals pkgs.stdenv.isDarwin [
            inputs.morlana.packages.${system}.default
            inputs.nix-darwin.packages.${system}.default
          ]
          ++ [ config.formatter ]
          ++ [ inputs.nix-auto-follow.packages.${system}.default ];

        shellHook = ''
          printf "\n🐢 Use \e[32;40mjust\e[0m to build the system."
          printf "\n💄 Use \e[32;40mtreefmt\e[0m to format the files."
          export NIX_CONFIG="extra-experimental-features = flakes nix-command pipe-operators"
        '';
      };
    };
}
