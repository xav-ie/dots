{
  ffmpeg,
  pkgs-unfree,
  python3Packages,
  stdenv,
  whisper-ctranslate2,
  writeNuApplication,
}:
writeNuApplication {
  name = "whisper-transcribe";
  runtimeInputs = [
    ffmpeg
    (python3Packages.python.withPackages (ps: [ ps.sounddevice ]))
    (if stdenv.isLinux then pkgs-unfree.pkgsCuda.whisper-ctranslate2 else whisper-ctranslate2)
  ];
  text = builtins.readFile ./whisper-transcribe.nu;
}
