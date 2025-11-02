_: {
  config = {
    programs.ssh = {
      enable = true;
      # Disable deprecated default config values
      enableDefaultConfig = false;
      # Apply to all hosts by default
      matchBlocks = {
        "*" = {
          # Send environment variables to support truecolor, locale, and terminal type
          sendEnv = [
            "COLORTERM"
            "TERM"
            "LANG"
            "LC_ALL"
          ];

          # If enabled, the remote server will use ALL keys from your local
          # ssh-agent for authenticating to other servers. This is suboptimal
          # since it must try every key in whatever order they were loaded.
          # Better approach: set up keys directly on the remote server and
          # configure which key to use for which host in the remote's SSH config.
          forwardAgent = false;
          # Use modern Ed25519 key by default for all hosts
          identityFile = "~/.ssh/id_ed25519";
          # cache SSH key passphrase for session
          addKeysToAgent = "yes";
          # attempt to reduce amount of data transfer
          compression = true;
          # Check we are connected every X seconds
          serverAliveInterval = 30;
          # Disconnect after X connection attempt failures
          serverAliveCountMax = 3;
          # Don't hash hostnames in known_hosts (easier to read)
          hashKnownHosts = false;
          # Standard location for known hosts file
          userKnownHostsFile = "~/.ssh/known_hosts";
          # Allow multiple SSH connections to a single host ride onto one
          # "master"/main manager.
          # Makes the first connection to a remote host "master" if the first,
          # and subsequent ones  use the main connection.
          controlMaster = "auto";
          # Path for control socket (when multiplexing enabled)
          controlPath = "~/.ssh/master-%r@%n:%p";
          # Keep SSH connections open for X time units after exit, or "no" (never)
          # This is useful for multiple git operations. Instead of creating new
          # SSH connection each time, you will be able to re-use the previous
          # connection for X time units!
          controlPersist = "5m";
        };
      };
    };
  };
}
