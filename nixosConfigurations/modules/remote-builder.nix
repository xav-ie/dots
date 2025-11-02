{ config, ... }:
{
  nix = {
    settings.trusted-users = [ config.defaultUser ];

    buildMachines = [
      {
        hostName = "stella";
        system = "aarch64-darwin";
        systems = [
          "aarch64-darwin"
          "x86_64-darwin"
        ];
        maxJobs = 4;
        speedFactor = 2;
        supportedFeatures = [
          "nixos-test"
          "benchmark"
          "big-parallel"
        ];
        protocol = "ssh-ng";
        sshUser = config.defaultUser;
      }
    ];

    distributedBuilds = true;
    settings.builders-use-substitutes = true;
  };

  programs.ssh.extraConfig = ''
    Host stella
      ServerAliveInterval 60
      ServerAliveCountMax 10
      ControlMaster auto
      ControlPath ~/.ssh/master-%r@%n:%p
      ControlPersist 10m
  '';
}
