# Home Assistant voice satellite (wake word, mic, speaker) over the ESPHome API.
# Its two wake word libraries aren't in nixpkgs; pymicro-wakeword vendors a
# prebuilt libtensorflowlite_c like nixpkgs' pyopen-wakeword does.
{
  lib,
  autoPatchelfHook,
  fetchFromGitHub,
  iproute2,
  python3Packages,
  which,
}:
let
  ps = python3Packages;

  pymicro-features = ps.buildPythonPackage rec {
    pname = "pymicro-features";
    version = "2.0.2";
    pyproject = true;
    src = fetchFromGitHub {
      owner = "rhasspy";
      repo = "pymicro-features";
      tag = "v${version}";
      hash = "sha256-bCvrsvifUxM7jfqBePmcYviZ5pIy1ZApq48Pu/5b7AM=";
    };
    build-system = [
      ps.setuptools
      ps.wheel
    ];
    pythonImportsCheck = [ "pymicro_features" ];
  };

  pymicro-wakeword = ps.buildPythonPackage rec {
    pname = "pymicro-wakeword";
    version = "2.5.0";
    pyproject = true;
    src = fetchFromGitHub {
      owner = "OHF-Voice";
      repo = "pymicro-wakeword";
      tag = "v${version}";
      hash = "sha256-hyCH0yMUyQbAER+kvIgdlMDSbH4RVq7tFaxSprqCdRw=";
    };
    postPatch = "python ./script/copy_lib";
    nativeBuildInputs = [ autoPatchelfHook ];
    build-system = [ ps.setuptools ];
    dependencies = [
      ps.numpy
      pymicro-features
    ];
    pythonImportsCheck = [ "pymicro_wakeword" ];
  };
in
ps.buildPythonApplication rec {
  pname = "linux-voice-assistant";
  version = "1.1.15";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "OHF-Voice";
    repo = "linux-voice-assistant";
    tag = "v${version}";
    hash = "sha256-n/d5+hwivoInpjrx5Wnv7WGPnyH9xmXFLD4Nvdc3M5A=";
  };

  # Wake words, sounds and version.txt live at the repo root, beside the module.
  postPatch = ''
    echo ${version} > version.txt
    substituteInPlace linux_voice_assistant/__main__.py \
      --replace-fail "_REPO_DIR = _MODULE_DIR.parent" "_REPO_DIR = Path('$out/share/linux-voice-assistant')"
    substituteInPlace linux_voice_assistant/util.py \
      --replace-fail 'Path(__file__).parent.parent / "version.txt"' "Path('$out/share/linux-voice-assistant/version.txt')"
  '';

  env.SETUPTOOLS_SCM_PRETEND_VERSION = version;

  build-system = [
    ps.setuptools
    ps.setuptools-scm
  ];
  dependencies = [
    ps.aioesphomeapi
    ps.getmac
    ps.mpv
    ps.netifaces2
    ps.numpy
    ps.pyopen-wakeword
    ps.soundcard
    ps.webrtc-noise-gain
    ps.websockets
    ps.zeroconf
    pymicro-wakeword
  ];
  pythonRelaxDeps = [
    "aioesphomeapi"
    "websockets"
  ];
  # nixpkgs ships python-mpv under the distribution name "mpv".
  pythonRemoveDeps = [
    "python-mpv"
    "types-protobuf"
  ];

  postInstall = ''
    mkdir -p $out/share/linux-voice-assistant
    cp -r sounds wakewords version.txt $out/share/linux-voice-assistant/
  '';

  # netifaces2 finds the default gateway by running `which ip`.
  makeWrapperArgs = [
    "--prefix PATH : ${
      lib.makeBinPath [
        iproute2
        which
      ]
    }"
  ];

  pythonImportsCheck = [ "linux_voice_assistant" ];
  meta.mainProgram = "linux-voice-assistant";
}
