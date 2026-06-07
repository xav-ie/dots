{
  flake.modules.nixos.linux = {
    config = {
      services.gnome.gnome-keyring.enable = true;
      programs.seahorse.enable = true;
    };
  };
}
