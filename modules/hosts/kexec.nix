# kexec — throwaway rescue system for the ext4 → btrfs migration.
#
# Build `.#nixosConfigurations.kexec.config.system.build.kexecTree`, run its
# `kexec-boot` script, and the machine soft-reboots into this image with the
# nvme root unmounted. Runs entirely from RAM, so it can repartition the disk
# it was launched from.
#
# Deliberately does NOT import flakeModules.nixos.{common,linux}: this needs to
# be small enough to sit in RAM, and it must not inherit praesidium's disko or
# fileSystems config.
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

      # SSH is the way back in if the console is unusable after the jump. Note
      # the machine's IP before kexecing — this image gets a fresh DHCP lease.
      services.openssh = {
        enable = true;
        settings.PermitRootLogin = "prohibit-password";
      };
      users.users.root.openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMW+HCZNdLZO3RVs9XCCw9iOeBprmfEfjTVsiuB81LOr"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB+cooWaT6xYXtD+5mlVQUfzbjhjO/Z8sxJLu8K1JfFC"
      ];

      # ── This is why the 2026-08-02 attempt was unreachable ─────────────────
      # `netboot-minimal.nix` sets
      #     hardware.enableRedistributableFirmware = lib.mkOverride 70 false;
      # so the image ships no linux-firmware. This board's NIC is a Realtek
      # RTL8125B (r8169), which needs rtl_nic/rtl8125b-2.fw to bring up a link,
      # and the wifi is an Intel AX210 (iwlwifi), which needs its own ucode.
      # Both stayed down -> no DHCP -> no SSH -> no way back into the machine.
      #
      # mkForce (priority 50) is REQUIRED: a plain `= true` is priority 100 and
      # loses to upstream's mkOverride 70, silently changing nothing.
      #
      # Costs ~1.4G of store in a RAM-resident image; this host has 31G.
      hardware.enableRedistributableFirmware = lib.mkForce true;

      # NetworkManager is dropped here on purpose. It only ever produced a DHCP
      # lease, and when that silently failed there was no address to fall back
      # to. Scripted networking can hold a fixed address AND run DHCP on the
      # same interface, so the machine is reachable at a known address even if
      # DHCP dies, while DHCP still supplies the route/DNS that `nixos-install`
      # needs to reach GitHub and the binary cache.
      networking = {
        hostName = "kexec-rescue";
        firewall.enable = false;
        networkmanager.enable = lib.mkForce false;
        useDHCP = false;

        # enp3s0 is the RTL8125B; it keeps this name in the rescue image
        # because NixOS uses the same predictable-naming rules.
        #
        # .240 was verified free by a full sweep of the /24 on 2026-08-02, and
        # is high enough to sit outside a typical .100-.200 DHCP pool. If your
        # router hands out .240, change it — a collision here costs you the
        # guaranteed way back in. Never use .177: that is praesidium's own lease.
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
        # Not 127.0.0.1 — praesidium's local resolver does not exist in a RAM
        # image, and without real DNS `nixos-install` cannot resolve github.com.
        nameservers = [
          "1.1.1.1"
          "8.8.8.8"
        ];
      };

      # kexec on UEFI frequently loses the EFI framebuffer, because the new
      # kernel never gets EFI boot services to remap it — that is why the
      # monitor stayed dark. Emit on serial too, so a board with a header or
      # BMC still has a console when the framebuffer is gone.
      boot.kernelParams = [
        "console=ttyS0,115200"
        "console=tty0"
      ];

      # Flake evaluation during nixos-install needs these. `pipe-operators` is
      # not optional: modules/claude/claude.nix uses the `|>` operator, so
      # without it `nixos-install --flake github:xav-ie/dots#praesidium` dies
      # at evaluation — which, run in the documented order, happens *after*
      # disko has already destroyed the disk.
      nix.settings.experimental-features = [
        "nix-command"
        "flakes"
        "pipe-operators"
      ];

      system.stateVersion = "23.05";
    };
}
