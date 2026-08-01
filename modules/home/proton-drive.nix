{
  flake.modules.homeManager.common =
    { pkgs, ... }:
    {
      # Scriptable Proton Drive access; `proton-drive auth login` signs in via the
      # browser and stores the session in the OS secret store.
      home.packages = [ pkgs.pkgs-mine.proton-drive-cli ];
    };
}
