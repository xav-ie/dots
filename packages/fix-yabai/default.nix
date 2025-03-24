{
  writeNuApplication,
  yabai,
  jq,
  nushell,
}:
# TODO: use https://github.com/shanyouli/nur-packages/blob/4365127bfdb0b97919c71d6763d9b9ea2c4d178f/nix/plib/nuenv.nix#L64

writeNuApplication {
  name = "fix-yabai";
  runtimeInputs = [
    yabai
    jq
    nushell
  ];

  text = # nu
    ''
      try { sudo yabai --load-sa };

      yabai -m query --windows
      | jq '.[].id'
      | lines
      | each { |line|
          try { yabai -m window $line --sub-layer normal }
        }
    '';
}
