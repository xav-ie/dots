# zellij-tab-name-update 📛

Update the current zellij tab name based on the directory you are in.

## Usage

```sh
nix run github:xav-ie/dots#zellij-tab-name-update
```

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

Then, in your zsh's `initContent` code:

```nix
zsh = {
  initContent = #zsh
  ''
    precmd() {
      ${inputs.xav-ie.packages.${pkgs.system}.zellij-tab-name-update}/bin/zellij-tab-name-update
    }
  '';
};
```

For bash, you will have you set `PROMPT_COMMAND` instead:

```nix
bash = {
  initContent = #bash
  ''
    PROMPT_COMMAND="${inputs.xav-ie.packages.${pkgs.system}.zellij-tab-name-update}/bin/zellij-tab-name-update; command2; ...;"
  '';
};
```

This is untested, so please open issue if you have problems!

[..](..)
