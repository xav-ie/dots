# kexec — throwaway rescue system. Runs entirely from RAM, so it can
# repartition the disk it was launched from. Build
# `.#nixosConfigurations.kexec.config.system.build.kexecTree` and run its
# `kexec-boot` script.
#
# Does not import flakeModules.nixos.{common,linux}: it must stay small enough
# for RAM and must not inherit praesidium's disko or fileSystems config.
{ inputs, ... }:
{
  configurations.nixos.kexec.module =
    {
      lib,
      modulesPath,
      pkgs,
      ...
    }:
    {
      imports = [ (modulesPath + "/installer/netboot/netboot-minimal.nix") ];

      nixpkgs.hostPlatform = "x86_64-linux";

      environment.systemPackages = [
        inputs.disko.packages.x86_64-linux.disko
        pkgs.btrfs-progs
        pkgs.e2fsprogs
        pkgs.git
        pkgs.gptfdisk
        pkgs.nixos-install-tools
        pkgs.parted
        pkgs.rsync
        pkgs.util-linux
      ];

      # The way back in if the console is unusable after the jump.
      services.openssh = {
        enable = true;
        settings.PermitRootLogin = "prohibit-password";
      };
      users.users.root.openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMW+HCZNdLZO3RVs9XCCw9iOeBprmfEfjTVsiuB81LOr"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB+cooWaT6xYXtD+5mlVQUfzbjhjO/Z8sxJLu8K1JfFC"
      ];

      # Without this the RTL8125B (rtl_nic/rtl8125b-2.fw) and AX210 have no
      # firmware and neither NIC links. mkForce is required: netboot-minimal
      # disables it at mkOverride 70, which a plain `= true` loses to. ~1.4G.
      hardware.enableRedistributableFirmware = lib.mkForce true;

      # Scripted networking, not NetworkManager, so a fixed address and DHCP
      # can share the interface — reachable at a known address if DHCP fails,
      # while DHCP still supplies the route nixos-install needs.
      networking = {
        hostName = "kexec-rescue";
        firewall.enable = false;
        networkmanager.enable = lib.mkForce false;
        useDHCP = false;

        # enp3s0 is the RTL8125B. .240 sits outside a typical .100-.200 DHCP
        # pool; never .177, which is praesidium's own lease.
        interfaces.enp3s0 = {
          useDHCP = true;
          ipv4.addresses = [
            {
              address = "192.168.1.240";
              prefixLength = 24;
            }
          ];
        };
        defaultGateway = "192.168.1.1";
        # Not 127.0.0.1: praesidium's local resolver does not exist here.
        nameservers = [
          "1.1.1.1"
          "8.8.8.8"
        ];
      };

      # kexec on UEFI frequently loses the EFI framebuffer, so emit on serial
      # too.
      boot.kernelParams = [
        "console=ttyS0,115200"
        "console=tty0"
      ];

      # nixos-install evaluates this flake, and modules/claude/claude.nix uses
      # the `|>` operator, so pipe-operators is not optional.
      nix.settings.experimental-features = [
        "nix-command"
        "flakes"
        "pipe-operators"
      ];

      system.stateVersion = "23.05";
    };
}
