# Gmail SOPS secrets and generated configs
# Secrets: app passwords + addresses
# Templates: himalaya config.toml (IMAP backend), neverestrc (sync), msmtprc (sending)
# Requires lib/common/user.nix (provides defaultUser option)
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config) defaultUser;
  emailData = import ../../lib/email-accounts.nix;

  mkHimalayaAccount =
    {
      name,
      addressPlaceholder,
      passFile,
      default ? false,
    }:
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
      auth.cmd = "cat ${passFile}"

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
    ''
      account ${name}
      host smtp.gmail.com
      port 465
      tls on
      tls_starttls off
      auth on
      from ${addressPlaceholder}
      user ${addressPlaceholder}
      passwordeval cat ${passFile}
    '';

  mkNeverestAccount =
    {
      name,
      addressPlaceholder,
      passFile,
      default ? false,
    }:
    ''
      [accounts.${name}]
      default = ${if default then "true" else "false"}
      folder.filters.include = [${
        lib.concatMapStringsSep ", " (f: "\"${f.gmailRemote}\"") emailData.folders
      }]

      left.backend.type = "maildir"
      left.backend.root-dir = "/home/${defaultUser}/.mail/${name}"

      left.folder.permissions.create = true
      left.folder.permissions.delete = true
      left.flag.permissions.update = true
      left.message.permissions.create = true
      left.message.permissions.delete = true

      right.backend.type = "imap"
      right.backend.host = "imap.gmail.com"
      right.backend.port = 993
      right.backend.encryption = "tls"
      right.backend.login = "${addressPlaceholder}"
      right.backend.auth.type = "password"
      right.backend.auth.cmd = "cat ${passFile}"

      right.folder.permissions.delete = false
      right.message.permissions.delete = false

      ${lib.concatMapStrings (
        f: "right.folder.aliases.${f.name} = \"${f.gmailRemote}\"\n"
      ) emailData.folders}
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
        content = ''
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
}
