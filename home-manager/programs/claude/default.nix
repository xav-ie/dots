{
  config,
  pkgs,
  ...
}:
let
  claude-wrapped = pkgs.symlinkJoin {
    name = "claude-wrapped";
    paths = [ pkgs.pkgs-mine.claude-code ];
    buildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/claude \
        --prefix PATH : "${config.home.homeDirectory}/.local/bin"
    '';
  };
in
{
  config = {
    home.packages = [ claude-wrapped ];

    home.file.".local/bin/claude" = {
      source = "${claude-wrapped}/bin/claude";
    };
  };
}
