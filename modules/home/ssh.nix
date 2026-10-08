{
  flake.modules.homeManager.common =
    { pkgs, ... }:
    {
      config = {
        programs.ssh = {
          enable = true;
          # Disable deprecated default config values
          enableDefaultConfig = false;
          # Attribute names become `Host <name>`; keys are upstream
          # ssh_config(5) directives.
          settings = {
            # Bare names never resolve (tailscale --accept-dns=false, dnsmasq
            # domain-needed), so tailnet hosts map to their MagicDNS names.
            "arca" = {
              HostName = "arca.gecko-bonito.ts.net";
              User = "root";
            };
            # The alias keeps known_hosts keyed on "nox".
            "nox" = {
              HostKeyAlias = "nox";
              HostName = "nox.gecko-bonito.ts.net";
            };
            # ssh-praesidium-route races cloudflared and tailnet probes in
            # parallel; whichever transport first proves reachable wins.
            # See packages/ssh-praesidium-route/ for the full racing logic.
            "praesidium" = {
              ProxyCommand = "${pkgs.pkgs-mine.ssh-praesidium-route}/bin/ssh-praesidium-route";
            };
            "*" = {
              # cache SSH key passphrase for session
              AddKeysToAgent = "yes";
              # attempt to reduce amount of data transfer
              Compression = true;
              # Allow multiple SSH connections to a single host ride onto one
              # "master"/main manager.
              # Makes the first connection to a remote host "master" if the first,
              # and subsequent ones  use the main connection.
              ControlMaster = "auto";
              # Path for control socket (when multiplexing enabled)
              ControlPath = "~/.ssh/master-%r@%n:%p";
              # Keep SSH connections open for X time units after exit, or "no" (never)
              # This is useful for multiple git operations. Instead of creating new
              # SSH connection each time, you will be able to re-use the previous
              # connection for X time units!
              ControlPersist = "5m";
              # If enabled, the remote server will use ALL keys from your local
              # ssh-agent for authenticating to other servers. This is suboptimal
              # since it must try every key in whatever order they were loaded.
              # Better approach: set up keys directly on the remote server and
              # configure which key to use for which host in the remote's SSH config.
              ForwardAgent = false;
              # Don't hash hostnames in known_hosts (easier to read)
              HashKnownHosts = false;
              # Use modern Ed25519 key by default for all hosts
              IdentityFile = "~/.ssh/id_ed25519";
              # Send environment variables to support truecolor, locale, and terminal type
              SendEnv = [
                "COLORTERM"
                "TERM"
                "LANG"
                "LC_ALL"
              ];
              # Disconnect after X connection attempt failures
              ServerAliveCountMax = 3;
              # Check we are connected every X seconds
              ServerAliveInterval = 30;
              # Standard location for known hosts file
              UserKnownHostsFile = "~/.ssh/known_hosts";
            };
          };
        };
      };
    };
}
