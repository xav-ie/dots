{ ... }:
{
  config = {
    home.file.".config/neovide/config.toml".text = # toml
      ''
        fork = false
        frame = "none"
        idle = true
        maximized = false
        no-multigrid = false
        srgb = false
        tabs = true
        theme = "auto"
        title-hidden = true
        vsync = true
        wsl = false
        [font]
            normal = [] # Will use the bundled Fira Code Nerd Font by default
            size = 14.0
      '';
  };
}
