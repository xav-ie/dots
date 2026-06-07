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
    {
      devShells.default = pkgs.mkShell {
        packages =
          (with pkgs; [
            just
            nix-diff
            nushell
          ])
          ++ (with config.packages; [
            nom-run
            nix-output-monitor
          ])
          ++ lib.optionals pkgs.stdenv.isLinux (
            with pkgs;
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
        '';
      };
    };
}
