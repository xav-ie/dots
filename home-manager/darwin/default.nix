{ ... }:
{
  imports = [
    ../programs/sketchybar
    ../programs/pueue
  ];

  config = {
    home = {
      stateVersion = "23.11";
      sessionVariables = { };
    };
  };
}
