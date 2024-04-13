{ inputs, outputs }:
{

  # For every flake input, aliases 'pkgs.inputs.${flake}' to
  # 'inputs.${flake}.packages.${pkgs.system}' or
  # 'inputs.${flake}.legacyPackages.${pkgs.system}'
  flake-inputs = final: _: {
    inputs = builtins.mapAttrs
      (_: flake:
        let
          legacyPackages = ((flake.legacyPackages or { }).${final.system} or { });
          packages = ((flake.packages or { }).${final.system} or { });
        in
        if legacyPackages != { } then legacyPackages else packages
      )
      inputs;
  };

  # Adds my custom packages
  additions = final: prev:
    import ../pkgs { pkgs = final; };

  modifications = final: prev: {
    ctpv = inputs.ctpv.packages.${final.system}.default;
    alacritty-theme = inputs.alacritty-theme.packages.${final.system};
    zjstatus = inputs.zjstatus.packages.${final.system}.default;
    ollama = inputs.ollama.packages.${final.system}.default;
    mpv = prev.mpv.override {
      scripts = with final.mpvScripts; [
        autoload # autoloads entries before and after current entry
        mpv-playlistmanager # resolves url titles, SHIFT+ENTER for playlist
        quality-menu # control video quality on the fly
        webtorrent-mpv-hook # extends mpv to handle magnet URLs
      ] ++
      # extends mpv to be controllable with MPD
      final.lib.optional (final.system == "x86_64-linux") final.mpvScripts.mpris
      ;
    };
    weechat = prev.weechat.override {
      configure = { availablePlugins, ... }: {
        scripts = with prev.weechatScripts; [
          # Idk how to use this one yet
          edit # edit messages in $EDITOR
          wee-slack # slack in weechat
          # I think weeslack already has way to facilitate notifications
          # weechat-notify-send # highlight and notify bindings to notify-send
          weechat-go # command pallette jumping
        ];
      };
    };

  };
}
