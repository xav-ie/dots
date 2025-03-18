{
  writeShellApplication,
  yabai,
  jq,
  nushell,
}:
# TODO: use https://github.com/shanyouli/nur-packages/blob/4365127bfdb0b97919c71d6763d9b9ea2c4d178f/nix/plib/nuenv.nix#L64

writeShellApplication {
  name = "fix-yabai";
  runtimeInputs = [
    yabai
    jq
    nushell
  ];

  text =
    let
      # TODO: format properly
      nuScript = # nu
        ''
          try { sudo yabai --load-sa };
          yabai -m query --windows | jq '.[].id' | lines | each {|line| try { yabai -m window $line --sub-layer normal }}
        '';
    in
    # sh
    ''
      # TODO: remove this, only here to pass shellcheck
      let line = ""
      nu -c "${nuScript}"
    '';
}
