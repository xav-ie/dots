# sudo by YubiKey touch: pam_rssh asks an ssh agent to sign a challenge with the
# YubiKey's OpenPGP authentication key, which needs a tap on every use. The key
# is plugged into whichever machine you're at, so sudo tries both agents:
#   - this machine's gpg-agent, for the key plugged in here;
#   - the agent forwarded from nox, for the key plugged in there.
# Without either, sudo falls back to the password.
#
# Prompts show where you are. At this computer (at-computer), yubikey-touch-popup
# says "Insert your
# YubiKey" while sudo waits for a missing key and "Touch your YubiKey" while it
# waits for a tap. From nox, nox's own yubikey-touch-prompt shows the touch; from
# collie or anywhere else, sudo goes straight on to the key checks.
{
  flake.modules.nixos.praesidium =
    { config, lib, pkgs, ... }:
    let
      # Only the touch-required key. NixOS defaults auth_key_file to the ssh
      # login keys, which would let the unprotected id_ed25519 sudo silently.
      # A store path, so the list is root-owned and can't be edited at runtime.
      sudoKeys = pkgs.writeText "sudo-authorized-keys" ''
        ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOqZYrFBIr97EUKJbHir26Q0CadLD4e3gtXufC7UaGTY
      '';

      # pam_exec hook before the key checks. At this computer with no YubiKey
      # plugged in, raise the popup's "insert" flag and hold sudo up to 30s for
      # the key; once it appears the key checks below can use it. Away from the
      # computer or already plugged in, it returns at once. Its result never
      # decides auth.
      waitForKey = pkgs.writeShellScript "sudo-yubikey-wait" ''
        PATH=${
          lib.makeBinPath [
            pkgs.coreutils
            pkgs.gnugrep
            pkgs.pkgs-mine.at-computer
          ]
        }
        [ "$PAM_TYPE" = auth ] || exit 0
        uid=$(id -u "$PAM_USER") || exit 0
        runtime=/run/user/$uid
        [ -d "$runtime" ] || exit 0

        # 1050 is Yubico's USB vendor id.
        key_present() { cat /sys/bus/usb/devices/*/idVendor 2>/dev/null | grep -qx 1050; }
        key_present && exit 0
        at-computer "$PAM_USER" >/dev/null || exit 0

        flag=$runtime/yubikey-insert
        trap 'rm -f "$flag"' EXIT
        trap 'exit 0' INT TERM
        install -m 0644 -o "$uid" /dev/null "$flag"
        for _ in $(seq 60); do
          # A moment for gpg's scdaemon to see the newly attached card.
          if key_present; then sleep 1; exit 0; fi
          sleep 0.5
        done
      '';

      rsshOrder = config.security.pam.services.sudo.rules.auth.rssh.order;
    in
    {
      # The forwarded agent.
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

      security.pam.services.sudo.rules.auth = {
        yubikey-wait = {
          order = rsshOrder - 200;
          control = "optional";
          modulePath = "${pkgs.pam}/lib/security/pam_exec.so";
          args = [
            "quiet"
            "${waitForKey}"
          ];
        };
        # This machine's gpg-agent, through the caller's SSH_AUTH_SOCK. Pointing
        # that at another agent gains nothing: only the YubiKey can sign for
        # sudoKeys. No cue: the popup does that job here.
        rssh-local = {
          order = rsshOrder - 100;
          control = "sufficient";
          modulePath = "${pkgs.pam_rssh}/lib/libpam_rssh.so";
          settings.auth_key_file = "${sudoKeys}";
        };
      };

      # Lets gpg's scdaemon reach the YubiKey over USB without pcscd.
      hardware.gpgSmartcards.enable = true;

      # Publishes GPG_1/GPG_0 while the local key waits for a touch; the popup
      # renders it instead of a libnotify toast.
      programs.yubikey-touch-detector = {
        enable = true;
        libnotify = false;
      };

      systemd.user.services.yubikey-touch-popup = {
        description = "YubiKey insert/touch popup";
        wantedBy = [ "graphical-session.target" ];
        partOf = [ "graphical-session.target" ];
        after = [ "graphical-session.target" ];
        # gtk4-layer-shell needs Wayland, whatever GDK_BACKEND the session set.
        environment.GDK_BACKEND = "wayland";
        serviceConfig = {
          ExecStart = lib.getExe pkgs.pkgs-mine.yubikey-touch-popup;
          Restart = "on-failure";
        };
      };

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
