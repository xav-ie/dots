{ pkgs, ... }:
{
  home.packages = [ pkgs.dconf ];

  dconf.settings = {
    # tell gtk applications to prefer dark mode, please!
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
    };
  };
}
