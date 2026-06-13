{
  appimageTools,
  coreutils,
  fetchurl,
  runCommand,
  stdenv,
}:
let
  pname = "openrgb";
  release = "0.9";
  releaseCommit = "b5f46e3";
  arch = builtins.elemAt (builtins.split "-" stdenv.hostPlatform.system) 0;
  version = builtins.concatStringsSep "_" [
    release
    arch
    releaseCommit
  ];

  src = fetchurl {
    url = "https://openrgb.org/releases/release_${release}/OpenRGB_${version}.AppImage";
    hash = "sha256-tVMBABLTo03AtXDhE410ZvAPCIFYzPn1SaUtiNYbHsA=";
  };

  contents = appimageTools.extract { inherit pname version src; };

  # The AppImage ships the device udev rules at usr/lib/udev/rules.d, which
  # NixOS's services.udev.packages doesn't scan. Surface them at lib/udev so
  # they get installed — needed for serverless `openrgb -p` to reach devices
  # without root (uaccess ACLs) when the --server daemon isn't running. The
  # bundled rules call /bin/chmod (ASUS TUF laptop lines); NixOS's udev rule
  # validator rejects non-store absolute paths, so rewrite it to coreutils.
  udevRules = runCommand "openrgb-udev-rules" { } ''
    install -Dm444 ${contents}/usr/lib/udev/rules.d/60-openrgb.rules \
      $out/lib/udev/rules.d/60-openrgb.rules
    substituteInPlace $out/lib/udev/rules.d/60-openrgb.rules \
      --replace-quiet /bin/chmod ${coreutils}/bin/chmod
  '';

  rulesFile = "${udevRules}/lib/udev/rules.d/60-openrgb.rules";
in
appimageTools.wrapType2 {
  inherit pname version src;

  extraInstallCommands = ''
    install -Dm444 ${rulesFile} $out/lib/udev/rules.d/60-openrgb.rules
  '';

  # OpenRGB decides whether to print "udev rules not installed" by checking for
  # the rules file at /etc and /usr/lib/udev inside its own process. The FHS
  # sandbox doesn't expose the host's /etc/udev, so bind the rules in at that
  # path — device access already works via the host-installed rules; this just
  # silences the false warning.
  extraBwrapArgs = [
    "--ro-bind ${rulesFile} /etc/udev/rules.d/60-openrgb.rules"
  ];
}
