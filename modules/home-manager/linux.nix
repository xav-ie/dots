{
  pkgs,
  pwnvim,
  ...
} @ inputs: {
  home = {
    packages = [pkgs.ripgrep pkgs.fd pkgs.curl pkgs.eza];
    # The state version is required and should stay at the version you
    # originally installed.
    stateVersion = "23.11";
    sessionVariables = {
    };
  };
  programs = {
  };
}
