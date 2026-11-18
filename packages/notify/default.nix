{
  lib,
  writeNuApplication,
  at-computer ? null,
  generate-kaomoji,
  libnotify,
  notifier ? null,
  notify-icons,
  openssh,
  ssh-client-host,
}:
writeNuApplication {
  name = "notify";
  runtimeInputs = [
    generate-kaomoji
    libnotify
    openssh
    ssh-client-host
  ];
  text = ''
    const NOTIFY_ICONS = "${notify-icons}"
    const NOTIFIER = ${
      if notifier == null then
        "null"
      else
        ''"${notifier}/Applications/Notifier.app/Contents/MacOS/notifier"''
    }
    const AT_COMPUTER = ${if at-computer == null then "null" else ''"${lib.getExe at-computer}"''}
  ''
  + builtins.readFile ./notify.nu;
}
