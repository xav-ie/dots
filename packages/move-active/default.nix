{
  writeText,
  writeShellApplication,
  jq,
  nushell,
  hyprland,
  stdenv,
}:
# TODO: use https://github.com/shanyouli/nur-packages/blob/4365127bfdb0b97919c71d6763d9b9ea2c4d178f/nix/plib/nuenv.nix#L64
writeShellApplication {
  name = "move-active";
  runtimeInputs = [
    jq
    nushell
    hyprland
  ];

  # disable shellcheck
  checkPhase = ''
    runHook preCheck
    ${stdenv.shellDryRun} "$target"
    runHook postCheck
  '';

  text =
    let
      nuScript = writeText "move-active.nu" (builtins.readFile ./move-active.nu);
    in
    # sh
    ''
      nu -c "use ${nuScript} *; $1"
    '';
}
