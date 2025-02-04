toplevel:
let
  inherit (toplevel) inputs;
in
{
  nur = inputs.nur.overlays.default;
  # For every flake input, aliases 'pkgs.inputs.${flake}' to
  # 'inputs.${flake}.packages.${pkgs.system}' or
  # 'inputs.${flake}.legacyPackages.${pkgs.system}'
  # flake-inputs = final: _: {
  #   inputs = builtins.mapAttrs (
  #     _: flake:
  #     let
  #       legacyPackages = ((flake.legacyPackages or { }).${final.system} or { });
  #       packages = ((flake.packages or { }).${final.system} or { });
  #     in
  #     if legacyPackages != { } then legacyPackages else packages
  #   ) inputs;
  # };

  # Adds my custom packages
  additions = final: _: import ../pkgs { pkgs = final; };

  modifications = final: prev: {
    ctpv = inputs.ctpv.packages.${final.system}.default;
    alacritty-theme =
      if final.stdenv.isLinux then inputs.alacritty-theme.packages.${final.system} else null;
    generate-kaomoji = inputs.generate-kaomoji.packages.${final.system}.default;
    morlana = if final.stdenv.isDarwin then inputs.morlana.packages.${final.system}.default else null;
    # ghostty = inputs.ghostty.packages.${final.system}.default;
    mpv = prev.mpv.override {
      scripts =
        with final.mpvScripts;
        [
          autoload # autoloads entries before and after current entry
          mpv-playlistmanager # resolves url titles, SHIFT+ENTER for playlist
          quality-menu # control video quality on the fly
          webtorrent-mpv-hook # extends mpv to handle magnet URLs
        ]
        ++
          # extends mpv to be controllable with MPD
          final.lib.optional final.stdenv.isLinux final.mpvScripts.mpris;
    };
    zjstatus = inputs.zjstatus.packages.${final.system}.default;
  };
}
