{
  appimageTools,
  fetchurl,
  openrgb,
  stdenv,
}:
let
  pname = "openrgb";
  release = "1.0";
  releaseCommit = "81bbe18";
  arch = builtins.elemAt (builtins.split "-" stdenv.hostPlatform.system) 0;
  version =
    [
      release
      arch
      releaseCommit
    ]
    |> builtins.concatStringsSep "_";

  src = fetchurl {
    url = "https://codeberg.org/OpenRGB/OpenRGB/releases/download/release_${release}/OpenRGB_${version}.AppImage";
    hash = "sha256-p32f6pqx5Z5ewrXOxKsi1Q8EM1lMToPrE95OXDz63r8=";
  };

  # The 1.0 AppImage no longer bundles the device udev rules, so take nixpkgs'
  # openrgb copy (same release, already store-path-patched for the udev rule
  # validator) — needed for serverless `openrgb -p` to reach devices without
  # root (uaccess ACLs) when the --server daemon isn't running.
  rulesFile = "${openrgb}/lib/udev/rules.d/60-openrgb.rules";
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
