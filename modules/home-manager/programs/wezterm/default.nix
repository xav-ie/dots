{ ... }:
{
  programs = {
    wezterm = {
      enable = true;
      extraConfig = # lua
        ''
          -- Pull in the wezterm API
          local wezterm = require 'wezterm'
          local mux = wezterm.mux

          wezterm.on("gui-startup", function()
            local tab, pane, window = mux.spawn_window{}
            window:gui_window():maximize()
          end)

          -- This table will hold the configuration.
          local config = {}

          -- In newer versions of wezterm, use the config_builder which will
          -- help provide clearer error messages
          if wezterm.config_builder then
            config = wezterm.config_builder()
          end

          -- This is where you actually apply your config choices

          -- For example, changing the color scheme:
          config = {
            color_scheme = 'Argonaut',
            enable_tab_bar = false,
            font = wezterm.font_with_fallback {
              -- 'Martian Mono', -- too decorated for my taste
              'Maple Mono',
              'CaskaydiaCove Nerd Font',
              'MonaspiceNe Nerd Font',
              'Fira Code Nerd Font',
              -- these fonts did not install properly from the package.
              -- I will have to investigate why, later. For now, I looked up
              -- their store path and installed manually from there
              -- 'Maple', 'Martian Mono', 
              -- This one is just not packaged at all:
              -- 'Twilio Sans Mono'

            },
            font_size = 12.0,
            macos_window_background_blur = 0,
            -- use_fancy_tab_bar = false
            window_background_opacity = 0.95,
            window_decorations = "RESIZE",
            window_padding = {
              left = 0,
              right = 0,
              top = 0,
              bottom = 0,
            },
          }

          -- and finally, return the configuration to wezterm
          return config
        '';
    };
  };
}
