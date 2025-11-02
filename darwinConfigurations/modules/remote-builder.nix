{ config, ... }:
{
  nix = {
    # Trust the builder user for remote operations
    settings.trusted-users = [ config.defaultUser ];

    # Configure praesidium as a remote builder
    buildMachines = [
      {
        # Tailscale hostname for praesidium
        hostName = "praesidium";
        # Build x86_64 Linux packages
        system = "x86_64-linux";
        # Also support building for Linux in general
        systems = [
          "x86_64-linux"
          "aarch64-linux"
        ];
        # Maximum number of parallel build jobs on praesidium
        maxJobs = 8;
        # Speed factor compared to local builds (higher = faster)
        # praesidium is likely faster than Mac for Linux builds
        speedFactor = 2;
        # Features that praesidium supports
        supportedFeatures = [
          "nixos-test"
          "benchmark"
          "big-parallel"
          "kvm"
        ];
        # Use SSH for connecting
        protocol = "ssh-ng";
        # SSH as your user (already has keys set up via Tailscale)
        sshUser = config.defaultUser;
        # Optional: use specific SSH key if needed
        # sshKey = "/Users/${config.defaultUser}/.ssh/id_ed25519";
      }
    ];

    # Distribute builds - try remote builders first, fallback to local
    distributedBuilds = true;

    # If a remote builder fails, build locally instead
    settings.builders-use-substitutes = true;
  };

  # Ensure SSH works properly for the builder
  programs.ssh.extraConfig = ''
    # Remote builder connection settings
    Host praesidium
      # Keep connection alive for builds
      ServerAliveInterval 60
      ServerAliveCountMax 10
      # Use connection multiplexing for faster builds
      ControlMaster auto
      ControlPath ~/.ssh/master-%r@%n:%p
      ControlPersist 10m
  '';
}
