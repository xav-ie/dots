({pkgs, ...} @ inputs: {
  # darwin prefs and config items
  programs.zsh.enable = true;
  environment = {
    shells = [pkgs.bash pkgs.zsh];
    loginShell = pkgs.zsh;
    pathsToLink = ["/Applications"];
  };
  nix.extraOptions = ''
    experimental-features = nix-command flakes
  '';
  fonts.fontDir.enable = true;
  fonts.fonts = [(pkgs.nerdfonts.override {fonts = ["Meslo"];})];
  services.nix-daemon.enable = true;
  # BECAUSE YA HAVE TO :/
  # https://github.com/nix-community/home-manager/issues/4026
  users.users.xavierruiz.home = "/Users/xavierruiz";
  system = {
    #packages = [pkgs.coreutils];
    keyboard.enableKeyMapping = true;
    keyboard.remapCapsLockToEscape = true;
    defaults = {
      finder = {
        AppleShowAllExtensions = true;
        _FXShowPosixPathInTitle = true;
      };
      dock = {
        autohide = true;
      };
      NSGlobalDomain.InitialKeyRepeat = 14;
      NSGlobalDomain.KeyRepeat = 1;
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
    casks = ["raycast" "slack"];
    taps = [];
    brews = ["mas"];
  };
})
