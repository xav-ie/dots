{ config, pkgs, ... }:
{
  config = {
    programs.atop = {
      enable = true;
      atopgpu.enable = true;
      netatop.enable = true;
      netatop.package = config.boot.kernelPackages.netatop.overrideAttrs (oldAttrs: {
        version = "3.2.2";
        src = pkgs.fetchurl {
          url = "https://www.atoptool.nl/download/netatop-3.2.2.tar.gz";
          hash = "sha256-UIqJd809HN1nWHoTwl46QUZHtI+S0c44/BOLWRSuo/Y=";
        };

        # Replicate all attributes from original package
        nativeBuildInputs = config.boot.kernelPackages.kernel.moduleBuildDependencies;
        buildInputs = [
          pkgs.kmod
          pkgs.zlib
        ];

        hardeningDisable = [ "pic" ];
        env.NIX_CFLAGS_COMPILE = toString [ "-Wno-error=implicit-fallthrough" ];

        makeFlags = oldAttrs.makeFlags or [ ];

        # Replace all original patches with our versions for 3.2.2
        patches = [
          ./netatop-fix-module-init.patch
          ./netatop-3.2.2-fix-netatopd-build.patch
          ./netatop-3.2.2-fix-paths.patch
        ];

        # preConfigure: changed */Makefile -> Makefile for 3.2.2, replace dkms with manual install
        preConfigure =
          let
            inherit (config.boot.kernelPackages) kernel;
          in
          ''
            patchShebangs mkversion
            sed -i -e 's,^KERNDIR.*,KERNDIR=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build,' \
                Makefile
            sed -i -e 's,/lib/modules.*extra,'$out'/lib/modules/${kernel.modDirVersion}/extra,' \
                -e s,/usr,$out, \
                -e /init.d/d \
                -e /depmod/d \
                -e '/cd.*\/usr\/src.*dkms/d' \
                -e '/[[:space:]]dkms /d' \
                -e s,/lib/systemd,$out/lib/systemd, \
                Makefile

            # Add manual kernel module install after removing dkms commands
            sed -i '/^install:.*netatop\.ko/a\		install -D netatop.ko -t '$out'/lib/modules/${kernel.modDirVersion}/extra' Makefile

            kmod=${pkgs.kmod} substituteAllInPlace netatop.service
          '';

        preInstall =
          let
            inherit (config.boot.kernelPackages) kernel;
          in
          ''
            mkdir -p $out/lib/systemd/system $out/bin $out/sbin $out/share/man/man{4,8}
            mkdir -p $out/lib/modules/${kernel.modDirVersion}/extra
          '';

      });
      setuidWrapper.enable = true;
    };

    # Override netatop.service to use current-system instead of booted-system
    # This allows the service to work without reboot when the module is added
    systemd.services.netatop = {
      serviceConfig = {
        # Clear the original ExecStartPre and replace with our version
        ExecStartPre = [
          "" # This clears all previous ExecStartPre
          "${pkgs.kmod}/bin/modprobe -d /run/current-system/kernel-modules netatop"
        ];
      };
    };
  };
}
