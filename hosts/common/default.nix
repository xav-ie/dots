{
  config,
  pkgs,
  inputs,
  ...
}:
{
  nix.registry = {
    # This setting is important because it makes things like:
    # `nix run nixpkgs#some-package` makes it use the same reference of packages as in your 
    # flake.lock, which helps prevent the package from being different every time you run it
    home-manager.flake = inputs.home-manager;
    nixpkgs.flake = inputs.nixpkgs;
    nur.flake = inputs.nur;
  };

  nixpkgs.config = {
    allowUnfree = true;
  };

  environment.systemPackages = (
    with pkgs;
    [
      # TODO: put these in a better place
      cache-command
      ff
      generate-kaomoji
      j
      jira-task-list
      jira-list
      notify
      nvim
      searcher
      uair-toggle-and-notify
      zellij-tab-name-update
    ]
  );
}
