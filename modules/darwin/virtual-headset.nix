# Virtual Headset (github.com/xav-ie/virtual-headset): the macOS agent behind the
# sketchybar `virtual_headset` item, plus the Virtual_Headset_Microphone driver.
# Its HID device and microphone access come from entitlements honored only
# because nox boots amfi_get_out_of_my_way=1.
{
  flake.modules.darwin.macos =
    { inputs, ... }:
    {
      imports = [ inputs.virtual-headset.darwinModules.default ];

      services.virtual-headset = {
        enable = true;
        firefox = true;
      };
    };
}
