{
  flake.modules.nixos.praesidium =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      # NixOS's nvidia module adds `services.udev.extraRules` that mknod each
      # /dev/nvidia* node via `bash -c 'mknod ...'`. Modern nvidia drivers
      # create the nodes themselves, so each mknod runs after-the-fact and
      # fails with EEXIST → udev logs "Process 'bash -c mknod ...' failed
      # with exit code 1" for every node every boot. Append `2>/dev/null || :`
      # to each mknod via `apply` so the rule succeeds either way.
      options.services.udev.extraRules = lib.mkOption {
        apply =
          rules:
          rules
          |>
            builtins.replaceStrings
              [
                "'mknod -m 666 /dev/nvidiactl c 195 255'"
                "done"
                "'mknod -m 666 /dev/nvidia-modeset c 195 254'"
                "'mknod -m 666 /dev/nvidia-uvm c $$(grep nvidia-uvm /proc/devices | cut -d \\  -f 1) 0'"
                "'mknod -m 666 /dev/nvidia-uvm-tools c $$(grep nvidia-uvm /proc/devices | cut -d \\  -f 1) 1'"
              ]
              [
                "'mknod -m 666 /dev/nvidiactl c 195 255 2>/dev/null || :'"
                "done 2>/dev/null || :"
                "'mknod -m 666 /dev/nvidia-modeset c 195 254 2>/dev/null || :'"
                "'mknod -m 666 /dev/nvidia-uvm c $$(grep nvidia-uvm /proc/devices | cut -d \\  -f 1) 0 2>/dev/null || :'"
                "'mknod -m 666 /dev/nvidia-uvm-tools c $$(grep nvidia-uvm /proc/devices | cut -d \\  -f 1) 1 2>/dev/null || :'"
              ];
      };

      config = lib.mkIf config.hardware.nvidia-container-toolkit.enable (
        let
          # After a driver bump the old kernel module stays loaded until reboot,
          # so NVML and CDI fail and every GPU unit restarted by the switch
          # fails activation. A failed ExecCondition skips the unit instead:
          # not counted as failed, and never auto-restarted.
          driverLoaded = pkgs.writeShellScript "nvidia-driver-loaded" ''
            [ "$(cat /sys/module/nvidia/version 2>/dev/null)" = ${config.hardware.nvidia.package.version} ]
          '';
          gpuContainers = lib.filterAttrs (
            _: c: lib.elem "--device=nvidia.com/gpu=all" c.extraOptions
          ) config.virtualisation.oci-containers.containers;
        in
        {
          systemd.services = lib.mkMerge [
            {
              nvidia-container-toolkit-cdi-generator = {
                # The CDI generator scans for driver files at FHS paths that don't
                # exist on NixOS (Xorg DDX libs, glvnd vendor JSON, OptiX/Vulkan
                # extras). The spec still generates correctly; --quiet suppresses
                # the warning chatter while keeping real errors.
                environment.NVIDIA_CTK_QUIET = "true";
                serviceConfig.ExecCondition = driverLoaded;
              };
            }
            (lib.mapAttrs' (
              name: _: lib.nameValuePair "podman-${name}" { serviceConfig.ExecCondition = driverLoaded; }
            ) gpuContainers)
          ];
        }
      );
    };
}
