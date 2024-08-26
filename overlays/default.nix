{
  inputs, # outputs
  ...
}:
{
  nur = inputs.nur.overlay;
  # For every flake input, aliases 'pkgs.inputs.${flake}' to
  # 'inputs.${flake}.packages.${pkgs.system}' or
  # 'inputs.${flake}.legacyPackages.${pkgs.system}'
  flake-inputs = final: _: {
    inputs = builtins.mapAttrs (
      _: flake:
      let
        legacyPackages = ((flake.legacyPackages or { }).${final.system} or { });
        packages = ((flake.packages or { }).${final.system} or { });
      in
      if legacyPackages != { } then legacyPackages else packages
    ) inputs;
  };

  # Adds my custom packages
  additions = final: _: import ../pkgs { pkgs = final; };

  modifications = final: prev: {
    ctpv = inputs.ctpv.packages.${final.system}.default;
    alacritty-theme = inputs.alacritty-theme.packages.${final.system};
    generate-kaomoji = inputs.generate-kaomoji.packages.${final.system}.default;
    ollama = inputs.ollama.packages.${final.system}.default;
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
          final.lib.optional (final.system == "x86_64-linux") final.mpvScripts.mpris;
    };
    zjstatus = inputs.zjstatus.packages.${final.system}.default;
    # TODO: wait for this PR to get merged and upstreamed:
    # https://github.com/metent/uair/pull/23
    # Then, the below can be removed!
    uair = prev.uair.override {
      rustPlatform.buildRustPackage =
        args:
        final.rustPlatform.buildRustPackage (
          args
          // {
            src = prev.fetchFromGitHub {
              owner = "thled";
              repo = prev.uair.src.repo;
              rev = "eb0789a8e8881ad99d83321b51240f63c71bc03f";
              hash = "sha256-QJuIncyBazaCD3LeaeypSCFL72Czn9fPKQYGULxoP0M=";
            };
            cargoHash = "sha256-QnVKb8DApG65eoNT7OIwpy4q2osaSMabk2lF6bC5+WQ=";
          }
        );
    };
  };
}
