{ ... }:
{
  config = {
    programs.wezterm = {
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
            -- The blue is too dark here
            -- color_scheme = 'Pro',
            -- Also here
            -- color_scheme = 'Windows High Contrast (base16)',

            -- Incorrectly makes teal a green shade
            -- color_scheme = 'Seti',

            -- decent, the red could be brighter
            -- color_scheme = 'Konsolas',

            -- colors could also be brighter for this one
            -- color_scheme = 'Builtin Dark',

            -- a little bit washed out on blue and purple
            -- you can at least see everything
            -- color_scheme = 'deep',

            -- acceptable, the colors could be more vibrant
            -- color_scheme = 'iTerm2 Dark Background',

            -- Background is too blue, but the colors are all correct
            color_scheme = 'Argonaut',

            -- The colors are a little pastel, but I kind of like it.
            -- white on black could be brighter, though
            -- color_scheme = 'Colors (base16)',

            window_background_gradient = {
              -- Can be "Vertical" or "Horizontal".  Specifies the direction
              -- in which the color gradient varies.  The default is "Horizontal",
              -- with the gradient going from left-to-right.
              -- Linear and Radial gradients are also supported; see the other
              -- examples below
              orientation = 'Vertical',

              -- l 70, c 100
              -- colors = {
              --   '#ff20af', '#ff2f79', '#ff5545', '#ff7600',
              --   '#fa9200', '#cfa800', '#9bb700', '#00ca31',
              --   '#00ce6f', '#00d1a9', '#00d2e1', '#00b7ff',
              --   '#00a3ff', '#bd89ff', '#ff67ff', '#ff41e5',
              -- },
              -- l 0, c 10
              -- decent
              -- colors = {
              --   '#160000', '#170000', '#170000', '#150000',
              --   '#110000', '#0b0000', '#030100', '#000400',
              --   '#000600', '#000700', '#000800', '#000807',
              --   '#00070e', '#000512', '#000314', '#000115',
              --   '#000014', '#060012', '#0e000e', '#130008',
              -- },
              -- l 0, c 5
              -- might as well not be there
              -- colors = {
              --   '#0d0000', '#0e0000', '#0e0000', '#0c0000',
              --   '#090000', '#060000', '#010100', '#000200',
              --   '#000300', '#000400', '#000400', '#000404',
              --   '#000307', '#00030a', '#00020b', '#00000c',
              --   '#00000c', '#03000a', '#070007', '#0b0004',
              -- },
              -- l 5, c 5
              -- mellows out the intensity of the colors
              -- not very noticeable on my desktop
              colors = {
                '#190e11', '#190e0e', '#190e0b', '#180f09',
                '#171007', '#151006', '#121107', '#0f1208',
                '#0b130b', '#08130e', '#051311', '#041313',
                '#041315', '#061317', '#091218', '#0c1118',
                '#101018', '#130f17', '#150f16', '#170e13',
              },

              -- "Linear", "Basis" and "CatmullRom" as supported.
              interpolation = 'Linear',

              -- How the colors are blended in the gradient.
              -- "Rgb", "LinearRgb", "Hsv" and "Oklab" are supported.
              -- The default is "Rgb".
              blend = 'Oklab',
              -- noise = 64,

              -- segment_size configures how many segments are present.
              -- segment_size = 20,
              -- segment_smoothness is how hard the edge is; 0.0 is a hard edge,
              -- 1.0 is a soft edge.
              -- segment_smoothness = 0.0,
            },


            enable_tab_bar = false,
            -- TODO: investigate these threads to see if I can enable again
            -- wez/wezterm#5103
            -- wez/wezterm#3121
            -- wez/wezterm#484
            -- wez/wezterm#1701
            front_end = "WebGpu",
            enable_wayland = false,
            font = wezterm.font_with_fallback {
              {
                family = 'Maple Mono',
                harfbuzz_features = {
                  'cv01=1', 'cv02=1', 'cv04=1', 'ss01=1', 'ss02=1', 'ss03=1', 'ss04=1', 'ss05=1'
                },
              },
              'CaskaydiaCove Nerd Font',
              'MonaspiceNe Nerd Font',
              'Fira Code Nerd Font',
              -- 'Martian Mono', -- too decorated for my taste
              -- these fonts did not install properly from the package.
              -- I will have to investigate why, later. For now, I looked up
              -- their store path and installed manually from there
              -- 'Maple', 'Martian Mono', 
              -- This one is just not packaged at all:
              -- 'Twilio Sans Mono'

            },
            font_size = 13.0,
            macos_window_background_blur = 15,
            -- use_fancy_tab_bar = false
            window_background_opacity = 0.80,
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
