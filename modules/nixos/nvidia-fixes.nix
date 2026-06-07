{
  flake.modules.nixos.praesidium =
    { config, lib, ... }:
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
            ]
            rules;
      };

      config = lib.mkIf config.hardware.nvidia-container-toolkit.enable {
        # The CDI generator scans for driver files at FHS paths that don't
        # exist on NixOS (Xorg DDX libs, glvnd vendor JSON, OptiX/Vulkan
        # extras). The spec still generates correctly; --quiet suppresses
        # the warning chatter while keeping real errors.
        systemd.services.nvidia-container-toolkit-cdi-generator.environment = {
          NVIDIA_CTK_QUIET = "true";
        };
      };
    };
}
