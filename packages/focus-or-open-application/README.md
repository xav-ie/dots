# focus-or-open-application 👓

Utilize the default MacOS `open` command to find and open the applications that you desire.

## Usage

Depending on your system:

```sh
nix run github:xav-ie/dots#focus-or-open-application AppNameHere
```

This will search all normal locations of .app files and then either focus the application if already open or open it if not.

It depends on yabai for the focus functionality.

If the app has multiple windows, it will choose the last window in the list of windows to enable window switching functionality. This is most helpful to say, break a meeting tab into its own window and ensure it never gets lost amongst the rest of your tabs.

## Installation

I recommend adding this to your NixOS flake if you want to use this long
term:

```nix
# ...
inputs = {
  xav-ie.url = "github:xav-ie/dots";
};
# ...
```

Then, wherever you add packages:

```nix
# ...
pkgs = with pkgs; [
  # ...
  # ...
  # ...
] ++ [
  inputs.xav-ie.packages.${pkgs.system}.focus-or-open-application
];
# ...
```

[..](..)
