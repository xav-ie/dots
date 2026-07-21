# Headless Proton Mail Bridge in a dedicated container on a private podman
# network shared only with the mcp container, so nothing on the host (or any
# other container) can reach its SMTP/IMAP. Two classes: the nixos container +
# network, and a homeManager login helper on the user's PATH.
let
  dataDir = "/var/lib/protonmail-bridge";
  network = "protonmail";
  image = "localhost/protonmail-bridge:latest";
in
{
  flake.modules.nixos.praesidium =
    { pkgs, ... }:
    let
      # Threaded IMAP-APPENDed drafts: stock Bridge never sets ParentID on
      # CreateDraft, so Proton doesn't link reply drafts to their conversation.
      # Builds upstream PR #526 directly (extracts the SMTP parent-resolver into a
      # shared package and calls it from the IMAP draft path). #526 is on master,
      # which needs Go >= 1.26.1, so bump the toolchain to bleeding's 1.26.x. Drop
      # this whole override once #526 lands in nixpkgs.
      # github.com/ProtonMail/proton-bridge/pull/526
      protonmail-bridge =
        (pkgs.protonmail-bridge.override {
          buildGoModule = pkgs.buildGoModule.override { go = pkgs.pkgs-bleeding.go; };
        }).overrideAttrs
          (old: {
            src = pkgs.fetchFromGitHub {
              owner = "m3kka";
              repo = "proton-bridge";
              rev = "54294ba8ef6a4fa218c942dba8ef62aac9cb6a33";
              hash = "sha256-SXiXzcnINcJPiMFVSwsyUml9LSRU+ktaQdi+Tjj6ubo=";
            };
            vendorHash = "sha256-jGFefDKPrYZ7QB3R/fRiEC6FPp6U77mJ2E/RXeylsvI=";
            # master added a FIDO2 (go-libfido2) cgo dep not in the 3.21.2 inputs.
            buildInputs = old.buildInputs ++ [ pkgs.libfido2 ];
          });

      runtimeInputs = [
        pkgs.coreutils
        protonmail-bridge
        pkgs.gnupg
        pkgs.pass
        pkgs.socat
        pkgs.gawk
      ];

      # Shared by both entrypoints so the one-time login and the headless daemon
      # use the same keychain. Bridge stores its vault key in a keychain and there
      # is no SecretService in a container, so bootstrap a passphrase-less gpg key
      # + pass store on the volume once (passphrase-less because the box must
      # unlock it unattended — same posture as a login-unlocked keyring).
      keychainInit = ''
        export HOME=${dataDir}
        export GNUPGHOME=${dataDir}/gnupg
        export PASSWORD_STORE_DIR=${dataDir}/pass
        mkdir -p "$GNUPGHOME" "$PASSWORD_STORE_DIR"
        chmod 700 "$GNUPGHOME"
        if [ ! -f "$PASSWORD_STORE_DIR/.gpg-id" ]; then
          gpg --batch --pinentry-mode loopback --passphrase "" \
            --quick-gen-key "protonmail-bridge" default default never
          keyid=$(gpg --list-keys --with-colons | awk -F: '/^fpr/{print $10; exit}')
          pass init "$keyid"
        fi
      '';

      # Container command: bootstrap the keychain, relay Bridge's loopback-only
      # SMTP/IMAP onto the container's interfaces so the mcp container can reach
      # them over the private network (0.0.0.0 is confined to THIS container's
      # netns, never the host; Bridge can't bind off-loopback itself), then run
      # headless. The relay listens on 2025/2143, NOT 1025/1143: a 0.0.0.0 listen
      # overlaps 127.0.0.1, so reusing Bridge's ports makes socat and Bridge race
      # for the same bind. Distinct ports keep them separate.
      bridge-entry = pkgs.writeShellApplication {
        name = "protonmail-bridge-entry";
        inherit runtimeInputs;
        text = ''
          ${keychainInit}
          # keepalive on both legs: without it an idle IMAP connection can go
          # half-open (no FIN) and the MCP's reads black-hole. Probes detect a
          # dead peer and tear the relay down so the client reconnects.
          ka=keepalive,keepidle=30,keepintvl=10,keepcnt=3
          socat TCP-LISTEN:2025,fork,reuseaddr,$ka TCP:127.0.0.1:1025,$ka &
          socat TCP-LISTEN:2143,fork,reuseaddr,$ka TCP:127.0.0.1:1143,$ka &
          exec protonmail-bridge --noninteractive
        '';
      };

      # One-time interactive login helper (invoked via the homeManager wrapper
      # below). Same keychain as the daemon.
      bridge-login = pkgs.writeShellApplication {
        name = "protonmail-bridge-login";
        inherit runtimeInputs;
        text = ''
          ${keychainInit}
          exec protonmail-bridge --cli
        '';
      };

      bridge-image = pkgs.dockerTools.buildLayeredImage {
        name = "localhost/protonmail-bridge";
        tag = "latest";
        contents = [
          bridge-entry
          bridge-login
          pkgs.cacert
          pkgs.bashInteractive # for the one-time `--cli` login exec
        ];
        # Bridge scans for the host OS release for update/telemetry info; without
        # it, every start logs an error and ships a crash report to Proton.
        extraCommands = ''
          mkdir -p etc
          cp ${pkgs.writeText "os-release" ''
            NAME=NixOS
            ID=nixos
            PRETTY_NAME="NixOS"
          ''} etc/os-release
        '';
        config = {
          Cmd = [ "${bridge-entry}/bin/protonmail-bridge-entry" ];
          Env = [
            "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
            "HOME=${dataDir}"
          ];
          Volumes."${dataDir}" = { };
        };
      };
    in
    {
      systemd.tmpfiles.rules = [ "d ${dataDir} 0700 root root -" ];

      # Private network shared only by this bridge and the mcp container. Not
      # `--internal`: Bridge needs egress to Proton, and isolation here comes from
      # nothing else being attached, not from blocking egress.
      systemd.services.protonmail-network = {
        after = [ "podman.service" ];
        requires = [ "podman.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          ${pkgs.podman}/bin/podman network exists ${network} \
            || ${pkgs.podman}/bin/podman network create ${network}
        '';
      };

      virtualisation.oci-containers.containers.protonmail-bridge = {
        autoStart = true;
        imageFile = bridge-image;
        inherit image;
        networks = [ network ];
        volumes = [ "${dataDir}:${dataDir}" ];
      };

      # Dual-home the mcp container: keep it on the default `podman` network so
      # traefik still routes to it (pinned via the label below), and add the
      # private network so it can reach the bridge by container name.
      virtualisation.oci-containers.containers.mcp = {
        networks = [
          "podman"
          network
        ];
        labels."traefik.docker.network" = "podman";
      };

      systemd.services.podman-protonmail-bridge = {
        after = [ "protonmail-network.service" ];
        requires = [ "protonmail-network.service" ];
      };
      systemd.services.podman-mcp = {
        after = [ "protonmail-network.service" ];
        requires = [ "protonmail-network.service" ];
      };
    };

  # `protonmail-login`: stop the headless daemon, open an interactive Bridge CLI
  # against the same volume, restart the daemon on exit (even if cancelled).
  # Inside: run `login`, then `list` + `info 0` to read the SMTP password into
  # `sudo sops set secrets/main.yaml '["proton"]["smtp_password"]' '"<pw>"'`.
  flake.modules.homeManager.linux =
    { pkgs, ... }:
    {
      home.packages = [
        (pkgs.writeShellApplication {
          name = "protonmail-login";
          text = ''
            echo "stopping bridge daemon..."
            sudo systemctl stop podman-protonmail-bridge
            trap 'echo "restarting bridge daemon..."; sudo systemctl start podman-protonmail-bridge' EXIT
            sudo podman run -it --rm \
              -v ${dataDir}:${dataDir} \
              ${image} protonmail-bridge-login
          '';
        })
      ];
    };
}
