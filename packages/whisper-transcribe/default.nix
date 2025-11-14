{
  ffmpeg,
  whisper-cpp,
  writeNuApplication,
}:
writeNuApplication {
  name = "whisper-transcribe";
  runtimeInputs = [
    ffmpeg
    whisper-cpp
  ];
  text = builtins.readFile ./whisper-transcribe.nu;
}
