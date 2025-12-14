{
  inputs,
  pkgs,
  ...
}:
{
  config = {
    programs.jjui = {
      enable = true;
    };

    programs.jujutsu = {
      enable = true;
      package =
        inputs.jj.outputs.packages.${pkgs.stdenv.hostPlatform.system}.jujutsu.overrideAttrs
          (_old: {
            sandboxProfile = "";
            # __sandboxProfile = null;
            doCheck = false;
          });
      settings = {
        "$schema" = "https://jj-vcs.github.io/jj/latest/config-schema.json";
        # https://jj-vcs.github.io/jj/latest/config/#commit-signing
        signing = {
          behavior = "own";
          backend = "gpg";
          # github@xav.ie
          key = "5B9134A9E7E7F965";
        };
        ui = {
          show-cryptographic-signatures = true;
        };
        user = {
          name = "Xavier Ruiz";
          email = "github@xav.ie";
        };

        "--scope" = [
          {
            # NB: only applies properly when there is active jj repo
            "--when"."repositories" = [ "~/Work/" ];
            user.email = "xavier@outsmartly.com";
            # xavier@outsmartly.com
            signing.key = "22420DD6C13E3EB7";
          }
        ];

        # TODO:
        # - pager
        # - diff editor
        # - rebase stuff
      };
    };
  };
}
