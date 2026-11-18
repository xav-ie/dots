# OBSBOT Meet 2 stays hot in its own sleep mode, whose processor keeps running. `webcam-power off`
# deauthorizes it on the USB bus (authorized=0): the kernel unbinds its drivers and
# leaves it unconfigured until `webcam-power on`. udev lets the video group flip
# the switch, so neither needs sudo.
{
  flake.modules.nixos.praesidium =
    { pkgs, ... }:
    let
      product = "fefb";
      vendor = "3564";

      webcam-power = pkgs.writeNuApplication {
        name = "webcam-power";
        text = # nu
          ''
            def camera [] {
              let found = (ls /sys/bus/usb/devices | get name | where {|d|
                ($"($d)/idVendor" | path exists) and ((open $"($d)/idVendor" | str trim) == "${vendor}") and ((open $"($d)/idProduct" | str trim) == "${product}")
              })
              if ($found | is-empty) { error make { msg: "OBSBOT Meet 2 is not plugged in" } }
              $found | first
            }

            def state [dev: string] {
              if ((open $"($dev)/authorized" | str trim) == "1") { "on" } else { "off" }
            }

            # Show whether the webcam is on the USB bus.
            def main [] {
              let dev = (camera)
              print $"webcam: (state $dev) \(($dev | path basename)\)"
            }

            # Deauthorize the webcam so it drops off the USB bus.
            def "main off" [] {
              let dev = (camera)
              "0" | save -f $"($dev)/authorized"
              print $"webcam: (state $dev)"
            }

            # Reauthorize the webcam.
            def "main on" [] {
              let dev = (camera)
              "1" | save -f $"($dev)/authorized"
              print $"webcam: (state $dev)"
            }
          '';
      };
    in
    {
      environment.systemPackages = [ webcam-power ];

      services.udev.extraRules = ''
        ACTION=="add", SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ATTR{idVendor}=="${vendor}", ATTR{idProduct}=="${product}", RUN+="${pkgs.coreutils}/bin/chgrp video /sys%p/authorized", RUN+="${pkgs.coreutils}/bin/chmod g+w /sys%p/authorized"
      '';
    };
}
