# Gmail SOPS secrets + generated configs (himalaya, neverest, msmtp).
{
  flake.modules.nixos.linux =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (config) defaultUser;
      emailData = import ./_accounts.nix;

      mkHimalayaAccount =
        {
          name,
          addressPlaceholder,
          passFile,
          default ? false,
        }:
        # toml
        ''
          [accounts.${name}]
          default = ${if default then "true" else "false"}
          display-name = "Xavier Ruiz"
          email = "${addressPlaceholder}"

          [accounts.${name}.backend]
          type = "imap"
          host = "imap.gmail.com"
          port = 993
          encryption.type = "tls"
          login = "${addressPlaceholder}"
          auth.type = "password"
          auth.cmd = "${pkgs.coreutils}/bin/cat ${passFile}"

          [accounts.${name}.folder.aliases]
          ${lib.concatMapStrings (f: "${f.name} = \"${f.gmailRemote}\"\n") emailData.folders}

          [accounts.${name}.message.send.backend]
          cmd = "${pkgs.msmtp}/bin/msmtp -t"
          type = "sendmail"
        '';

      mkMsmtpAccount =
        {
          name,
          addressPlaceholder,
          passFile,
        }:
        # conf
        ''
          account ${name}
          host smtp.gmail.com
          port 465
          tls on
          tls_starttls off
          auth on
          from ${addressPlaceholder}
          user ${addressPlaceholder}
          passwordeval ${pkgs.coreutils}/bin/cat ${passFile}
        '';

      mkNeverestAccount =
        {
          name,
          addressPlaceholder,
          passFile,
          default ? false,
        }:
        # Gmail is the account's only source and the local pimdir store its
        # destination, so the two merge two-way and `retain` keeps bodies on
        # disk. The store lives under $XDG_STATE_HOME/neverest/${name}.
        # toml
        ''
          [accounts.${name}]
          default = ${if default then "true" else "false"}
          retain = true

          imap.server = "imaps://imap.gmail.com:993"
          imap.sasl.plain.username = "${addressPlaceholder}"
          imap.sasl.plain.password.command = "${pkgs.coreutils}/bin/cat ${passFile}"

          imap.collection.filter.include = [${
            lib.concatMapStringsSep ", " (f: "\"${f.gmailRemote}\"") emailData.folders
          }]

          imap.collection.create = false
          imap.collection.delete = false
          imap.item.create = true
          imap.item.delete = false
        '';
    in
    {
      config.sops = {
        secrets = lib.mkMerge (
          lib.concatMap (acc: [
            {
              "gmail/${acc.secretsId}_pass" = {
                owner = defaultUser;
                mode = "0400";
              };
            }
            {
              "gmail/${acc.secretsId}_address" = {
                owner = defaultUser;
                mode = "0400";
              };
            }
          ]) emailData.accounts
        );

        templates."himalaya-config" = {
          owner = defaultUser;
          mode = "0400";
          path = "/home/${defaultUser}/.config/himalaya/config.toml";
          content = lib.concatStringsSep "\n" (
            map (
              acc:
              mkHimalayaAccount {
                inherit (acc) name default;
                addressPlaceholder = config.sops.placeholder."gmail/${acc.secretsId}_address";
                passFile = config.sops.secrets."gmail/${acc.secretsId}_pass".path;
              }
            ) emailData.accounts
          );
        };

        templates."msmtprc" =
          let
            defaultAccount =
              (lib.findFirst (acc: acc.default) (builtins.head emailData.accounts) emailData.accounts).name;
          in
          {
            owner = defaultUser;
            mode = "0400";
            path = "/home/${defaultUser}/.config/msmtp/config";
            content = # conf
              ''
                defaults
                tls_trust_file /etc/ssl/certs/ca-certificates.crt

                ${lib.concatStringsSep "\n" (
                  map (
                    acc:
                    mkMsmtpAccount {
                      inherit (acc) name;
                      addressPlaceholder = config.sops.placeholder."gmail/${acc.secretsId}_address";
                      passFile = config.sops.secrets."gmail/${acc.secretsId}_pass".path;
                    }
                  ) emailData.accounts
                )}
                account default : ${defaultAccount}
              '';
          };

        templates."neverestrc" = {
          owner = defaultUser;
          mode = "0400";
          path = "/home/${defaultUser}/.config/neverest/config.toml";
          content = lib.concatStringsSep "\n" (
            map (
              acc:
              mkNeverestAccount {
                inherit (acc) name default;
                addressPlaceholder = config.sops.placeholder."gmail/${acc.secretsId}_address";
                passFile = config.sops.secrets."gmail/${acc.secretsId}_pass".path;
              }
            ) emailData.accounts
          );
        };
      };
    };
}
