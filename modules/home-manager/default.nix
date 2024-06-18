{ pkgs, ... }:
{
  imports = [
    ./programs/alacritty
    ./programs/git
    ./programs/lf
    ./programs/starship
    ./programs/wezterm
    ./programs/zellij
    ./programs/zsh
  ];
  home = {
    packages =
      with pkgs;
      [
        curl
        delta
        fd
        ffmpeg
        go-jira
        gh
        gnumake
        (jira-cli-go.overrideAttrs (oldAttrs: {
          postInstall = ''
            mv $out/bin/jira $out/bin/jira-unfree
          '';
        }))
        magic-wormhole-rs # send files easily
        moar # the best pager
        uair
        unzip
        tree
        wget
        zip
      ]
      ++ [ ollama ];
    # The state version is required and should stay at the version you
    # originally installed.
    stateVersion = "23.11";
    sessionVariables = {
      BROWSER = "firefox";
      EDITOR = "$HOME/Projects/xnixvim/result/bin/nvim";
      LANG = "en_US.UTF-8";
      LC_ALL = "en_US.UTF-8";
      # causes bug if set. dont do it!
      BAT_PAGER = "";
      PAGER = ''bat -p --pager=\"moar -quit-if-one-screen\" --terminal-width=$(expr $COLUMNS - 4)'';
      MOAR = "-quit-if-one-screen";
      TERMINAL = "kitty";
      # get more colors
      HSTR_CONFIG = "hicolor";
      # leading space hides commands from history
      HISTCONTROL = "ignorespace";
      # increase history file size (default is 500)
      HISTFILESIZE = 10000;
      SOMETHING_RANDOM = 12;
      PATH = "$HOME/.config/scripts/:$PATH";
    };
  };
  programs = {
    # atuin = {
    #   enable = true;
    #   settings.style = "compact";
    # };
    bat = {
      enable = true;
      config = {
        theme = "ansi";
        pager = "moar -quit-if-one-screen";
        paging = "auto";
        style = "plain";
        wrap = "character";
      };
    };
    btop.enable = true;
    direnv = {
      enable = true;
      # very important, allows caching of build-time deps
      nix-direnv.enable = true;
    };
    eza = {
      enable = true;
      git = true;
      icons = true;
    };
    fzf.enable = true;
    jq.enable = true;
    kitty = {
      enable = true;
      keybindings = {
        "alt+h" = ''send_text all \x1bh'';
        "alt+j" = ''send_text all \x1bj'';
        "alt+k" = ''send_text all \x1bk'';
        "alt+l" = ''send_text all \x1bl'';
      };
      settings = {
        background = "#0a0a0f";
        background_blur = 10;
        background_opacity = "0.80";
        clipboard_control = "write-clipboard write-primary read-clipboard read-primary";
        copy_on_select = "yes";
        cursor = "#ff0000";
        font_family = "Maple Mono";
        font_size = "13.0";
        hide_window_decorations = "yes";
        macos_quit_when_last_window_closed = "yes";
      };

      # kitty +list-fonts --psnames | grep Maple
      extraConfig =
        let
          mapleFontFeatures = "+cv01 +cv02 +cv04 +ss01 +ss02 +ss03 +ss04 +ss05";
        in
        ''
          font_features MapleMono-Bold ${mapleFontFeatures}
          font_features MapleMono-BoldItalic ${mapleFontFeatures}
          font_features MapleMono-Italic ${mapleFontFeatures}
          font_features MapleMono-Light ${mapleFontFeatures}
          font_features MapleMono-LightItalic ${mapleFontFeatures}
          font_features MapleMono-Regular ${mapleFontFeatures}
        '';
    };
    mpv.enable = true;
    ripgrep.enable = true;
    thefuck.enable = true;
    watson.enable = true;
    zoxide.enable = true;
  };
  home.file.".inputrc".source = ./dotfiles/inputrc;
  home.file.".config/scripts/localip".source = ./dotfiles/localip;
  # There has got to be a better way to do this :(
  home.file.".config/scripts/timeUtils.sh".source = ./dotfiles/timeUtils.sh;
  home.file.".config/scripts/colorUtils.sh".source = ./dotfiles/colorUtils.sh;
  home.file.".config/scripts/generate_tokens.sh".source = ./dotfiles/generate_tokens.sh;
  home.file.".config/scripts/remove_video_silence.py".source = ./dotfiles/remove_video_silence.py;
  home.file.".config/gh-dash/config.yml".source = ./dotfiles/gh-dash/config.yml;
  home.file.".config/uair/uair.toml".source = ./dotfiles/uair.toml;
  home.file.".config/pijul/config.toml".source = ./dotfiles/pijul/config.toml;
}
