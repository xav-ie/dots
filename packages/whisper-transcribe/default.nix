{
  curl,
  ffmpeg,
  python3Packages,
  whisper-cpp,
  writeNuApplication,
}:
writeNuApplication {
  name = "whisper-transcribe";
  runtimeInputs = [
    curl
    ffmpeg
    whisper-cpp
    # list-devices only: capture-device enumeration for `stream --capture`.
    (python3Packages.python.withPackages (ps: [ ps.sounddevice ]))
  ];
  text = builtins.readFile ./whisper-transcribe.nu;
}
