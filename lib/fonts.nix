{
  pkgs,
  lib ? pkgs.lib,
  ...
}:
let
  fontDefs = {
    sans = {
      name = "Inter";
      package = pkgs.inter;
      features = [ ];
    };
    serif = {
      name = "Libertinus Serif";
      package = pkgs.libertinus;
      features = [ ];
    };
    mono = {
      name = "Maple Mono NF";
      package = pkgs.maple-mono.NF;
      features = [
        "cv01"
        "cv02"
        "ss01"
        "ss02"
        "ss03"
        "ss04"
        "ss05"
      ];
    };
    emoji = {
      name = "Apple Color Emoji";
      package = pkgs.pkgs-mine.apple-emoji-linux;
      features = [ ];
    };
  };

  fontName = fontKey: fontDefs.${fontKey}.name;
  fontPackage = fontKey: fontDefs.${fontKey}.package;
  fontFeatures = fontKey: fontDefs.${fontKey}.features;

  fontPackages = lib.attrValues (lib.mapAttrs (_k: v: v.package) fontDefs);
in
{
  # Central font configuration for all systems (NixOS, nix-darwin, home-manager)
  fonts = {
    # Helper functions
    name = fontName;
    package = fontPackage;
    features = fontFeatures;

    packages =
      fontPackages
      ++ (with pkgs; [
        maple-mono.truetype-autohint
        noto-fonts-color-emoji
      ])
      ++ (with pkgs.nerd-fonts; [
        # I like all these fonts a lot. You can test them by going to programmingfonts.org
        # However, the real names are to the right. I imagine it was renamed this way for
        # licensing reasons
        caskaydia-cove # "CaskaydiaCove Nerd Font"
        fira-code
        hasklug
        jetbrains-mono
        martian-mono
        meslo-lg
        # also in general packages??
        monaspace # "MonaspiceNe Nerd Font"
        # These ones should be in nerdfonts, but I guess they just aren't...
        # You can find them above in package installs :(
        # I think this is due to upstream not putting them in releases for some
        # reason:
        # https://github.com/ryanoasis/nerd-fonts/releases/
        # "Cascadia Code"
        # "Maple"
        # "Martian Mono"
        # "MonoLisa"
        # "Twilio Sans Mono" # this one may be included in future release:
        # https://github.com/ryanoasis/nerd-fonts/pull/1465
      ]);

    configs = {
      gtk = {
        name = fontName "sans";
        package = fontPackage "sans";
        size = 14;
      };
      ghostty = {
        font-family-1 = fontName "mono";
        font-family-2 = fontName "emoji";
        font-size = 15;
        font-features = fontFeatures "mono";
      };
      sketchybar = {
        icon-font = "${fontName "mono"}:Normal:24.0";
        label-font = "${fontName "mono"}:Normal:14.0";
      };
      waybar = {
        font-family = fontName "mono";
        font-size = 18;
      };
    };
  };
}
