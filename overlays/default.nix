toplevel:
let
  inherit (toplevel) inputs;
in
{
  nur = inputs.nur.overlays.default;
  nuenv = inputs.nuenv.overlays.default;

  modifications = final: _prev: {
    alacritty-theme =
      if final.stdenv.isLinux then inputs.alacritty-theme.packages.${final.system} else null;
    ctpv = inputs.ctpv.packages.${final.system}.default;
    generate-kaomoji = inputs.generate-kaomoji.packages.${final.system}.default;
    pkgs-bleeding = inputs.nixpkgs-bleeding.legacyPackages.${final.system};
    pkgs-mine = toplevel.self.packages.${final.system};
    writeNuApplication = final.nuenv.writeShellApplication;
    zjstatus = inputs.zjstatus.packages.${final.system}.default;
  };
}
