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

  modifications = final: _prev: {
    pkgs-bleeding = inputs.nixpkgs-bleeding.legacyPackages.${final.system};
    pkgs-mine = toplevel.self.packages.${final.system};

    ctpv = inputs.ctpv.packages.${final.system}.default;
    alacritty-theme =
      if final.stdenv.isLinux then inputs.alacritty-theme.packages.${final.system} else null;
    generate-kaomoji = inputs.generate-kaomoji.packages.${final.system}.default;
    morlana = if final.stdenv.isDarwin then inputs.morlana.packages.${final.system}.default else null;
    zjstatus = inputs.zjstatus.packages.${final.system}.default;
  };
}
