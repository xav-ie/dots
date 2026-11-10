# sudo by YubiKey touch: pam_rssh asks the ssh agent forwarded from nox to sign a
# challenge with the YubiKey's OpenPGP authentication key, which needs a tap on
# every use. Without the forwarded agent or the key, sudo falls back to the
# password.
{
  flake.modules.nixos.praesidium =
    { pkgs, ... }:
    let
      # Only the touch-required key. NixOS defaults auth_key_file to the ssh
      # login keys, which would let the unprotected id_ed25519 sudo silently.
      # A store path, so the list is root-owned and can't be edited at runtime.
      sudoKeys = pkgs.writeText "sudo-authorized-keys" ''
        ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOqZYrFBIr97EUKJbHir26Q0CadLD4e3gtXufC7UaGTY
      '';
    in
    {
      security.pam.rssh = {
        enable = true;
        settings = {
          auth_key_file = "${sudoKeys}";
          # Shells here point SSH_AUTH_SOCK at the local gpg-agent, and herdr
          # panes outlive the ssh login that started them, so read the forwarded
          # agent from the stable path sshrc maintains below instead.
          ssh_agent_addr = "/home/$user/.ssh/agent-forwarded";
          cue = true;
          cue_prompt = "Touch the YubiKey";
        };
      };
      security.pam.services.sudo.rssh = true;

      # sshd runs this for every login (sessions, commands, herdr --remote), with
      # SSH_AUTH_SOCK set to the forwarded agent when there is one. The newest
      # forwarding login wins; once it disconnects the link dangles and sudo
      # falls back to the password.
      environment.etc."ssh/sshrc".text = ''
        if [ -S "$SSH_AUTH_SOCK" ]; then
          ln -sfn "$SSH_AUTH_SOCK" "$HOME/.ssh/agent-forwarded"
        fi
      '';
    };
}
