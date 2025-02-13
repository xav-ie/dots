# see https://github.com/shanyouli/dotfiles/blob/9667d4779116236ab5f68010c3600aa90947faa2/nix/my/nuenv.nix
{
  lib,
  pkgs,
}:
let
  makeBinPathArray =
    packages:
    let
      binOutputs = builtins.filter (x: x != null) (map (pkg: lib.getOutput "bin" pkg) packages);
    in
    map (output: output + "/bin") binOutputs;
  toNu = v: "(\"${lib.escape [ "\"" "\\" ] (builtins.toJSON v)}\" | from json)";
in
# see @https://github.com/hallettj/nuenv/blob/writeShellApplication/lib/writeShellApplication.nix
{
  /*
    The name of the script to write.

    Type: String
  */
  name,
  /*
    The shell script's text, not including a shebang.

    Type: String
  */
  text,
  /*
    Inputs to add to the shell script's `$PATH` at runtime.

    Type: [String|Derivation]
  */
  runtimeInputs ? [ ],
  /*
    Extra environment variables to set at runtime.

    Type: AttrSet
  */
  runtimeEnv ? null,
  /*
    `stdenv.mkDerivation`'s `meta` argument.

    Type: AttrSet
  */
  meta ? { },
  /*
    The `checkPhase` to run. Defaults to `shellcheck` on supported
    platforms and `bash -n`.

    The script path will be given as `$target` in the `checkPhase`.

    Type: String
  */
  checkPhase ? null,
  /*
    Extra arguments to pass to `stdenv.mkDerivation`.

    :::{.caution}
    Certain derivation attributes are used internally,
    overriding those could cause problems.
    :::

    Type: AttrSet
  */
  derivationArgs ? { },
  nushell ? pkgs.nushell,
}:
pkgs.writeTextFile {
  inherit name meta derivationArgs;
  executable = true;
  destination = "/bin/${name}";
  allowSubstitutes = true;
  preferLocalBuild = false;
  text =
    ''
      #!${nushell}/bin/nu
    ''
    + lib.optionalString (runtimeEnv != null) ''

      load-env ${toNu runtimeEnv}
    ''
    + lib.optionalString (runtimeInputs != [ ]) ''

      $env.PATH = ${toNu (makeBinPathArray runtimeInputs)} ++ $env.PATH
    ''
    + ''
      ${text}
    '';
  checkPhase =
    if checkPhase == null then
      ''
        runHook preCheck
        ${nushell}/bin/nu --commands "nu-check '$target'"
        runHook postCheck
      ''
    else
      checkPhase;
}
