{
  lib,
  pkgs,
  outputs,
  ...
}:
{
  imports = [ ../common ];
  # darwin prefs and config items
  programs.zsh.enable = true;
  environment = {
    loginShell = pkgs.zsh;
    shells = [
      pkgs.bash
      pkgs.zsh
    ];
    systemPackages = with pkgs; [
      coreutils
      # These fonts should be included with `nerdfonts`, 
      # but I guess they are just general packages
      # "Cascadia Code"
      # "Maple"
      # "Martian Mono"
      # "Monaspace Neon"
      # The real names are to the right if different
      cascadia-code # "CaskaydiaCove Nerd Font"
      monaspace # "Monspace Neon" => "MonaspiceNe Nerd Font"
      # I had to manually install these from the store path, there is something going wrong on install
      maple-mono
      martian-mono
      # These two are not packaged at all:
      # "MonoLisa" # idk why this is not included yet in nerdfonts
      # "Twilio Sans Mono" # <== may change very soon, open pr to add it.
    ];
    pathsToLink = [ "/Applications" ];
    # use the version of nix that is from nix-darwin and home-manager and
    # disable using /nix/var/nix/profiles/default and ~/.nixprofile
    profiles = lib.mkForce [
      "/run/current-system/sw"
      "/etc/profiles/per-user/xavierruiz"
    ];
  };
  # unfortunately, this must be done in nix-darwin
  fonts.fontDir.enable = true;
  fonts.fonts = [
    (pkgs.nerdfonts.override {
      fonts = [
        # I like all these fonts a lot. You can test them by going to programmingfonts.org
        # However, the real names are to the right. I imagine it was renamed this way for 
        # licensing reasons
        "FiraCode"
        "Hasklig"
        "JetBrainsMono"
        "Meslo"
        # also in general packages??
        "Monaspace" # "MonaspiceNe Nerd Font"
        # These ones should be in nerdfonts, but I guess they just aren't...
        # You can find them above in package installs :(
        # I think this is due to upstream not putting them in releases for some reason:
        # https://github.com/ryanoasis/nerd-fonts/releases/
        # "Cascadia Code"
        # "Maple"
        # "Martian Mono"
        # "MonoLisa"
        # "Twilio Sans Mono" # this one may be included in future release:
        # https://github.com/ryanoasis/nerd-fonts/pull/1465
      ];
    })
  ];
  # allow sudo to use touch id
  security.pam.enableSudoTouchIdAuth = true;
  services = {
    nix-daemon.enable = true;
    # a lot of this is taken from https://github.com/shaunsingh/nix-darwin-dotfiles/commit/a457a0b2d0e68d810e3503f84217db8698dd9533
    yabai = {
      enable = true;
      enableScriptingAddition = true;
      config =
        let
          spacing = 0;
        in
        {
          focus_follows_mouse = "autoraise";
          mouse_follows_focus = "off";
          mouse_drop_action = "stack";
          window_placement = "second_child";
          window_opacity = "off";
          window_topmost = "on";
          window_shadow = "off";
          active_window_opacity = "1.0";
          normal_window_opacity = "1.0";
          split_ratio = "0.50";
          auto_balance = "on";
          mouse_modifier = "fn";
          mouse_action1 = "move";
          mouse_action2 = "resize";
          layout = "stack";
          top_padding = spacing;
          bottom_padding = spacing;
          left_padding = spacing;
          right_padding = spacing;
          window_gap = spacing;
        };
    };
    skhd = {
      enable = true;
      skhdConfig = # sh
        ''
          # I really like application driven window management. I just want simple keybindings to
          # just go where I want. Only downside is new bindings must be added for new apps.
          ctrl - 1 : osascript -e 'tell application "kitty" to activate'
          ctrl - 2 : osascript -e 'tell application "Firefox" to activate'
          ctrl - 3 : osascript -e 'tell application "Slack" to activate'
          ctrl - 4 : osascript -e 'tell application "zoom.us" to activate'
          ctrl - 5 : osascript -e 'tell application "Finder" to activate'
          ctrl - 6 : osascript -e 'tell application "Messages" to activate'
          ctrl - 7 : osascript -e 'tell application "Safari" to activate'
          ctrl + alt - 1 : osascript -e 'tell application "kitty" to activate'
          ctrl + alt - 2 : osascript -e 'tell application "Firefox" to activate'
          ctrl + alt - 3 : osascript -e 'tell application "Slack" to activate'
          ctrl + alt - 4 : osascript -e 'tell application "zoom.us" to activate'
          ctrl + alt - 5 : osascript -e 'tell application "Finder" to activate'
          ctrl + alt - 6 : osascript -e 'tell application "Messages" to activate'
          ctrl + alt - 7 : osascript -e 'tell application "Safari" to activate'

          ctrl + alt - h : yabai -m space --focus prev
          ctrl + alt - j : yabai -m window --focus stack.next
          ctrl + alt - k : yabai -m window --focus stack.prev
          ctrl + alt - l : yabai -m space --focus next

          ctrl + alt - q : yabai -m window --space prev
          ctrl + alt - w : yabai -m space --focus prev
          ctrl + alt - e : yabai -m space --focus next
          ctrl + alt - r : yabai -m window --space next

          ctrl + alt - f : yabai -m window --toggle float;\
           yabai -m window --grid 4:4:1:1:2:2

          ctrl + alt - s : yabai -m window --toggle sticky;\
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
    onActivation = {
      cleanup = "zap"; # destroy app config and app on removal from nix-darwin
    };
    masApps = {
      Klack = 6446206067;
      Magnet = 441258766;
      Twingate = 1501592214;
    };
    casks = [
      "bitwarden"
      "chromium"
      "firefox"
      "protonvpn"
      "raycast"
      "slack"
      "zoom"
    ];
    taps = [ ];
    brews = [ "mas" ];
  };

  nixpkgs = {
    overlays = builtins.attrValues outputs.overlays;
    # Allow unfree packages
    config.allowUnfree = true;
    # now you don't have to pass --impure when trying to run nix commands
    config.allowUnfreePredicate = _: true;
  };
}
