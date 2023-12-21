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
  services.nix-daemon.enable = true;
  # BECAUSE YA HAVE TO :/
  # https://github.com/nix-community/home-manager/issues/4026
  users.users.xavierruiz.home = "/Users/xavierruiz";
  system = {
    defaults = {
      dock = {
        autohide = true;
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
