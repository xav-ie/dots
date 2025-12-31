{
  ffmpeg,
  whisper-ctranslate2,
  writeNuApplication,
}:
writeNuApplication {
  name = "whisper-transcribe";
  runtimeInputs = [
    ffmpeg
    whisper-ctranslate2
  ];
  text = builtins.readFile ./whisper-transcribe.nu;
}
