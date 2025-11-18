{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.mpv;
  modernzPkg = pkgs.mpvScripts.modernz;
  # Override autosub to use our custom subliminal with fixed dependencies
  autosub-custom = pkgs.mpvScripts.autosub.override {
    python3Packages = pkgs.python3.pkgs // {
      subliminal = pkgs.subliminal-custom;
    };
  };
in
{
  options.programs.mpv = {
    settings.enable-webtorrent = lib.mkEnableOption "enable-webtorrent";
  };
  config = {
    home.packages = lib.optional cfg.settings.enable-webtorrent pkgs.pciutils;

    programs.mpv = {
      enable = true;

      scripts =
        (with pkgs.mpvScripts; [
          autoload # autoloads entries before and after current entry
          mpv-playlistmanager # resolves url titles, SHIFT+ENTER for playlist
          quality-menu # control video quality on the fly (Shift+F for video Alt+F for audio)
          skipsilence # increase playback speed during silence
          thumbfast # thumbnailer
          modernz # more modern UI
        ])
        ++ [
          autosub-custom # automatically find and download subtitles (uses custom subliminal 2.4.0)
        ]
        # extends mpv to handle magnet URLs
        ++ lib.optional cfg.settings.enable-webtorrent pkgs.mpvScripts.webtorrent-mpv-hook
        ++
          # extends mpv to be controllable with MPD
          lib.optional pkgs.stdenv.isLinux pkgs.mpvScripts.mpris;

      settings.enable-webtorrent = true;

      config = {
        # Use yt-dlp instead of youtube-dl (use full path)
        # Enable skipsilence by default
        # Use browser cookies for YouTube authentication (fixes 403 errors and enables Premium)
        script-opts = "ytdl_hook-ytdl_path=${lib.getExe config.programs.yt-dlp.package},skipsilence-enabled=yes";
        # Disable built-in OSC to use ModernZ instead
        osc = "no";
        # Disable built-in OSD on seek to show ModernZ OSC instead
        osd-on-seek = "no";
      };

      bindings = {
        # Show OSC when seeking with arrow keys
        "LEFT" = "seek -10; script-message-to modernz osc-show";
        "RIGHT" = "seek 10; script-message-to modernz osc-show";
        "UP" = "seek 60; script-message-to modernz osc-show";
        "DOWN" = "seek -60; script-message-to modernz osc-show";
        "Shift+LEFT" = "seek -60; script-message-to modernz osc-show";
        "Shift+RIGHT" = "seek 60; script-message-to modernz osc-show";
        "Shift+UP" = "seek 300; script-message-to modernz osc-show";
        "Shift+DOWN" = "seek -300; script-message-to modernz osc-show";

        # Quality menu keybindings
        "F" = "script-binding quality_menu/video_formats_toggle";
        "Alt+f" = "script-binding quality_menu/audio_formats_toggle";

        # No shaders by default (use Ctrl+1-6 to enable)
        # Anime4K shader profiles - Optimized shaders for higher-end GPU
        "CTRL+1" =
          ''no-osd change-list glsl-shaders set "~~/shaders/Anime4K_Clamp_Highlights.glsl:~~/shaders/Anime4K_Restore_CNN_VL.glsl:~~/shaders/Anime4K_Upscale_CNN_x2_VL.glsl:~~/shaders/Anime4K_AutoDownscalePre_x2.glsl:~~/shaders/Anime4K_AutoDownscalePre_x4.glsl:~~/shaders/Anime4K_Upscale_CNN_x2_M.glsl"; show-text "Anime4K: Mode A (HQ)"'';
        "CTRL+2" =
          ''no-osd change-list glsl-shaders set "~~/shaders/Anime4K_Clamp_Highlights.glsl:~~/shaders/Anime4K_Restore_CNN_Soft_VL.glsl:~~/shaders/Anime4K_Upscale_CNN_x2_VL.glsl:~~/shaders/Anime4K_AutoDownscalePre_x2.glsl:~~/shaders/Anime4K_AutoDownscalePre_x4.glsl:~~/shaders/Anime4K_Upscale_CNN_x2_M.glsl"; show-text "Anime4K: Mode B (HQ)"'';
        "CTRL+3" =
          ''no-osd change-list glsl-shaders set "~~/shaders/Anime4K_Clamp_Highlights.glsl:~~/shaders/Anime4K_Upscale_Denoise_CNN_x2_VL.glsl:~~/shaders/Anime4K_AutoDownscalePre_x2.glsl:~~/shaders/Anime4K_AutoDownscalePre_x4.glsl:~~/shaders/Anime4K_Upscale_CNN_x2_M.glsl"; show-text "Anime4K: Mode C (HQ)"'';
        "CTRL+4" =
          ''no-osd change-list glsl-shaders set "~~/shaders/Anime4K_Clamp_Highlights.glsl:~~/shaders/Anime4K_Restore_CNN_VL.glsl:~~/shaders/Anime4K_Upscale_CNN_x2_VL.glsl:~~/shaders/Anime4K_Restore_CNN_M.glsl:~~/shaders/Anime4K_AutoDownscalePre_x2.glsl:~~/shaders/Anime4K_AutoDownscalePre_x4.glsl:~~/shaders/Anime4K_Upscale_CNN_x2_M.glsl"; show-text "Anime4K: Mode A+A (HQ)"'';
        "CTRL+5" =
          ''no-osd change-list glsl-shaders set "~~/shaders/Anime4K_Clamp_Highlights.glsl:~~/shaders/Anime4K_Restore_CNN_Soft_VL.glsl:~~/shaders/Anime4K_Upscale_CNN_x2_VL.glsl:~~/shaders/Anime4K_AutoDownscalePre_x2.glsl:~~/shaders/Anime4K_AutoDownscalePre_x4.glsl:~~/shaders/Anime4K_Restore_CNN_Soft_M.glsl:~~/shaders/Anime4K_Upscale_CNN_x2_M.glsl"; show-text "Anime4K: Mode B+B (HQ)"'';
        "CTRL+6" =
          ''no-osd change-list glsl-shaders set "~~/shaders/Anime4K_Clamp_Highlights.glsl:~~/shaders/Anime4K_Upscale_Denoise_CNN_x2_VL.glsl:~~/shaders/Anime4K_AutoDownscalePre_x2.glsl:~~/shaders/Anime4K_AutoDownscalePre_x4.glsl:~~/shaders/Anime4K_Restore_CNN_M.glsl:~~/shaders/Anime4K_Upscale_CNN_x2_M.glsl"; show-text "Anime4K: Mode C+A (HQ)"'';

        # Clear all shaders
        "CTRL+0" = ''no-osd change-list glsl-shaders clr ""; show-text "GLSL shaders cleared"'';
      };
    };

    # Link Anime4K shaders from nixpkgs package
    xdg.configFile =
      lib.listToAttrs (
        map (shader: {
          name = "mpv/shaders/${shader}";
          value = {
            source = "${pkgs.anime4k}/${shader}";
          };
        }) [
          "Anime4K_Clamp_Highlights.glsl"
          "Anime4K_Restore_CNN_VL.glsl"
          "Anime4K_Restore_CNN_Soft_VL.glsl"
          "Anime4K_Restore_CNN_M.glsl"
          "Anime4K_Restore_CNN_Soft_M.glsl"
          "Anime4K_Upscale_CNN_x2_VL.glsl"
          "Anime4K_Upscale_CNN_x2_M.glsl"
          "Anime4K_Upscale_Denoise_CNN_x2_VL.glsl"
          "Anime4K_AutoDownscalePre_x2.glsl"
          "Anime4K_AutoDownscalePre_x4.glsl"
        ]
      )
      // {
        "mpv/script-opts/modernz.conf".source = ./modernz.conf;
        "mpv/script-opts/thumbfast.conf".source = ./thumbfast.conf;
        # Copy the fonts from the modernz package to mpv/fonts/
        "mpv/fonts/fluent-system-icons.ttf".source = "${modernzPkg}/share/fonts/fluent-system-icons.ttf";
        "mpv/fonts/material-design-icons.ttf".source =
          "${modernzPkg}/share/fonts/material-design-icons.ttf";
      };

    xdg.mimeApps.defaultApplications = {
      "video/*" = [ "mpv.desktop" ];
    };
    home.sessionVariables = {
      # `ani-cli` now prefers to launch `iina`, but I like `mpv`!
      ANI_CLI_PLAYER = "mpv";
    };
  };
}
