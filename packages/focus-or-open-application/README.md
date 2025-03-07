# focus-or-open-application 👓

Utilize the default MacOS `open` command to find and open the applications that you desire.

## Usage

Depending on your system:

```sh
nix run github:xav-ie/dots#focus-or-open-application AppNameHere
```

This will search all normal locations of .app files and then either focus the application if already open or open it if not.

It depends on yabai for the focus functionality.

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
