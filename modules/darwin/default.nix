({pkgs, ...} @ inputs: {
  # darwin prefs and config items
  programs.zsh.enable = true;
  environment = {
    loginShell = pkgs.zsh;
    shells = [pkgs.bash pkgs.zsh];
    systemPackages = [pkgs.coreutils];
    pathsToLink = ["/Applications"];
  };
  nix.extraOptions = ''
    experimental-features = nix-command flakes
  '';
  fonts.fontDir.enable = true;
  fonts.fonts = [(pkgs.nerdfonts.override {fonts = ["Meslo"];})];
  # allow sudo to use touch id
  security.pam.enableSudoTouchIdAuth = true;
  services = {
    nix-daemon.enable = true;
    # a lot of this is taken from https://github.com/shaunsingh/nix-darwin-dotfiles/commit/a457a0b2d0e68d810e3503f84217db8698dd9533
    yabai = {
      enable = true;
      enableScriptingAddition = false;
      config = {
        window_border = "on";
        window_border_width = 5;
        active_window_border_color = "0xff3B4252";
        normal_window_border_color = "0xff2E3440";
        focus_follows_mouse = "autoraise";
        mouse_follows_focus = "off";
        mouse_drop_action = "stack";
        window_placement = "second_child";
        window_opacity = "off";
        window_topmost = "on";
        window_shadow = "on";
        active_window_opacity = "1.0";
        normal_window_opacity = "1.0";
        split_ratio = "0.50";
        auto_balance = "on";
        mouse_modifier = "fn";
        mouse_action1 = "move";
        mouse_action2 = "resize";
        layout = "bsp";
        top_padding = 9;
        bottom_padding = 9;
        left_padding = 9;
        right_padding = 9;
        window_gap = 9;
      };
    };
    skhd = {
      enable = true;
      skhdConfig = ''
        ctrl + alt - h : yabai -m window --focus west
        ctrl + alt - j : yabai -m window --focus south
        ctrl + alt - k : yabai -m window --focus north
        ctrl + alt - l : yabai -m window --focus east
        # Fill space with window
        ctrl + alt - 0 : yabai -m window --grid 1:1:0:0:1:1
        # Move window
        ctrl + alt - e : yabai -m window --display 1; yabai -m display --focus 1
        ctrl + alt - d : yabai -m window --display 2; yabai -m display --focus 2
        ctrl + alt - f : yabai -m window --space next; yabai -m space --focus next
        ctrl + alt - s : yabai -m window --space prev; yabai -m space --focus prev
        # Close current window
        ctrl + alt - w : $(yabai -m window $(yabai -m query --windows --window | jq -re ".id") --close)
        # Rotate tree
        ctrl + alt - r : yabai -m space --rotate 90
        # Open application
        ctrl + alt - enter : alacritty
        ctrl + alt - e : emacs
        ctrl + alt - b : open -a Safari
        ctrl + alt - t : yabai -m window --toggle float;\
          yabai -m window --grid 4:4:1:1:2:2
        ctrl + alt - p : yabai -m window --toggle sticky;\
          yabai -m window --toggle topmost;\
          yabai -m window --toggle pip
      '';
    };
  };
  # BECAUSE YA HAVE TO :/
  # https://github.com/nix-community/home-manager/issues/4026
  users.users.xavierruiz.home = "/Users/xavierruiz";
  system = {
    defaults = {
      dock = {
        autohide = true;
        autohide-delay = 0.0;
        static-only = true;
        wvous-tl-corner = 2;
        wvous-tr-corner = 1;
        wvous-br-corner = 1;
        wvous-bl-corner = 1;
      };
      finder = {
        AppleShowAllExtensions = true;
        QuitMenuItem = true;
        ShowPathbar = true;
        ShowStatusBar = true;
        _FXShowPosixPathInTitle = true;
      };
      NSGlobalDomain.InitialKeyRepeat = 14;
      NSGlobalDomain.KeyRepeat = 1;
      screencapture.disable-shadow = true;
      trackpad = {
        Clicking = true;
        Dragging = true;
      };
    };
    keyboard = {
      enableKeyMapping = true;
      remapCapsLockToEscape = true;
    };
  };
  homebrew = {
    enable = true;
    caskArgs.no_quarantine = true; # do not prompt for updates
    global.brewfile = true; # track brews in a file
    masApps = {
      Klack = 6446206067;
      Magnet = 441258766;
      Twingate = 1501592214;
    };
    casks = [
      "bitwarden"
      "codewhisperer"
      "qutebrowser"
      "raycast"
      "slack"
      "spacelauncher"
      "zoom"
    ];
    taps = [];
    brews = ["mas"];
  };
})
