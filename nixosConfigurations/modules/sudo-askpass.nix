{
  pkgs,
  ...
}:
let
  sudo-askpass-script = pkgs.writeShellScript "sudo-askpass-wrapper" ''
    export SUDO_ASKPASS="${pkgs.pkgs-mine.zenity-askpass}/bin/zenity-askpass"
    exec /run/wrappers/bin/sudo -A "$@"
  '';
in
{
  security.wrappers.sudo-askpass = {
    owner = "root";
    group = "root";
    source = "${sudo-askpass-script}";
    setuid = true;
  };
}
