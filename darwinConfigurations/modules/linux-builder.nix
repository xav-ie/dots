{ user, ... }:
{
  nix.settings.trusted-users = [ user ];
  nix.linux-builder.enable = true;
}
