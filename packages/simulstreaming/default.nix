{
  lib,
  makeWrapper,
  python3,
  src,
}:

let
  python = python3.withPackages (
    ps: with ps; [
      librosa
      soundfile
      torch
      torchaudio
      tqdm
      tiktoken
      triton
    ]
  );
in

python3.pkgs.buildPythonApplication {
  pname = "simulstreaming";
  version = "unstable";
  pyproject = false;

  inherit src;

  # No setup.py, just scripts
  dontBuild = true;
  dontCheck = true;

  # Fix triton compatibility - newer triton doesn't support kernel.src manipulation
  patches = [ ./triton-compatibility.patch ];

  nativeBuildInputs = [
    makeWrapper
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/simulstreaming
    cp -r . $out/lib/simulstreaming/

    mkdir -p $out/bin

    # Create wrapper for server
    makeWrapper ${lib.getExe python} $out/bin/simulstreaming-server \
      --add-flags "$out/lib/simulstreaming/simulstreaming_whisper_server.py" \
      --prefix PYTHONPATH : "$out/lib/simulstreaming"

    # Create wrapper for file transcription
    makeWrapper ${lib.getExe python} $out/bin/simulstreaming \
      --add-flags "$out/lib/simulstreaming/simulstreaming_whisper.py" \
      --prefix PYTHONPATH : "$out/lib/simulstreaming"

    runHook postInstall
  '';

  meta = with lib; {
    description = "State-of-the-art simultaneous speech transcription using Whisper with AlignAtt policy";
    homepage = "https://github.com/ufal/SimulStreaming";
    license = licenses.mit;
    maintainers = [ ];
    platforms = platforms.linux;
  };
}
