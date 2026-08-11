{
  flake.modules.homeManager.common =
    {
      gpgKeys,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (pkgs.stdenv) isLinux;

      # Prime the agent cache for both commit-signing keys (personal, work) and
      # the ssh key gpg-agent serves for git pushes. Run from a terminal you
      # own: git's gpg wrapper passes `--pinentry-mode cancel` when it has no
      # tty, so an uncached key fails there rather than prompting on someone
      # else's pane.
      gpg-unlock =
        pkgs.writeShellScriptBin "gpg-unlock" # sh
          ''
            for k in ${gpgKeys |> lib.attrValues |> map (key: key.id) |> lib.concatStringsSep " "}; do
              # `--pinentry-mode cancel` fails rather than prompting, so only
              # keys the agent has not cached yet cost you a passphrase.
              echo unlock | ${pkgs.gnupg}/bin/gpg --pinentry-mode cancel --clearsign -u "$k" -o /dev/null 2>/dev/null ||
                echo unlock | ${pkgs.gnupg}/bin/gpg --clearsign -u "$k" -o /dev/null
            done
            # The ssh-agent protocol carries no ttyname, so gpg-agent prompts on
            # whichever tty it has on record. Without this it has none, picks the
            # graphical pinentry, and refuses the signature on a headless box.
            ${pkgs.gnupg}/bin/gpg-connect-agent updatestartuptty /bye >/dev/null
            ${pkgs.openssh}/bin/ssh-add -T "$HOME/.ssh/id_ed25519.pub"
          '';
    in
    {
      programs.gpg = {
        enable = true;
      };

      services.gpg-agent = {
        enable = true;
        enableSshSupport = true;
        # unlock once per login: the cache dies with the agent, nothing else
        defaultCacheTtl = 34560000;
        maxCacheTtl = 34560000;
        defaultCacheTtlSsh = 34560000;
        maxCacheTtlSsh = 34560000;
      }
      // lib.optionalAttrs isLinux {
        pinentry.package = pkgs.pkgs-mine.pinentry-auto;
      };

      home.packages = [
        gpg-unlock
      ]
      ++ lib.optionals isLinux [
        pkgs.pkgs-mine.pinentry-auto
      ];
    };
}
