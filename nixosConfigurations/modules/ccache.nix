{ config, ... }:
{
  config = {
    # Enable ccache for faster C/C++ compilation
    nix.settings = {
      # Allow Nix sandbox to access ccache directory
      extra-sandbox-paths = [
        config.programs.ccache.cacheDir
      ];
    };

    programs.ccache = {
      enable = true;
      # Store cache in user's home directory
      cacheDir = "/var/cache/ccache";
      packageNames = [
        # Add packages that benefit from ccache here
        # "onnxruntime" would go here if we wanted system-wide caching
      ];
    };

    # Create ccache directory with proper permissions
    systemd.tmpfiles.rules = [
      "d /var/cache/ccache 0770 root nixbld -"
    ];

    # Configure ccache to work with Nix's -frandom-seed flag
    environment.etc."ccache.conf".text = ''
      # Allow ccache to work despite Nix's -frandom-seed
      sloppiness = random_seed

      # Increase cache size for large builds like ONNX Runtime
      max_size = 20G

      # Enable compression to save disk space
      compression = true
      compression_level = 6
    '';
  };
}
