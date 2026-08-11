{
  flake.modules.homeManager.common =
    { gpgKeys, pkgs, ... }:
    let
      delta-jj = pkgs.writeNuApplication {
        name = "delta-jj";
        runtimeInputs = [ pkgs.delta ];
        text = ./delta-jj.nu |> builtins.readFile;
      };
    in
    {
      config = {
        programs.jjui = {
          enable = true;
        };

        programs.jujutsu = {
          enable = true;
          settings = {
            "$schema" = "https://jj-vcs.github.io/jj/latest/config-schema.json";
            # https://jj-vcs.github.io/jj/latest/config/#commit-signing
            signing = {
              behavior = "own";
              backend = "gpg";
              key = gpgKeys.personal.id;
            };
            ui = {
              show-cryptographic-signatures = true;

              diff-formatter = "${delta-jj}/bin/delta-jj";
            };
            user = {
              name = "Xavier Ruiz";
              inherit (gpgKeys.personal) email;
            };

            "--scope" = [
              {
                # NB: only applies properly when there is active jj repo
                "--when"."repositories" = [ "~/Work/" ];
                user.email = gpgKeys.work.email;
                signing.key = gpgKeys.work.id;
              }
            ];

            # TODO:
            # - pager
            # - diff editor
            # - rebase stuff
          };
        };
      };
    };
}
