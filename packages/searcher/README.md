# searcher 🔎

Easily search and enter shell of any valid package provider!

Nixpkgs searching script with fzf. Lets you easily search and enter
shell of a package without having to look it up on nixpkgs search.

## Usage

Depending on your system:

```sh
nix run github:xav-ie/dots#searcher
```

This will search all of nixpkgs and output fzf list of all of them.
Hitting enter on a result will enter you into a shell of that package.

```sh
searcher
```

This will search all of nixpkgs with your query and output fzf list of
all of them. Hitting enter on a result will enter you into a shell of
that package.

```sh
searcher query_without_spaces
```

This will search all of nixpkgs with your query and output fzf list of
all of them. Hitting enter on a result will enter you into a shell of
that package.

```sh
searcher nixpkgs query with spaces
```

Basically, to use spaces in your search, you need to specify where to
search. You can search other places too:

```sh
searcher nixpkgs/21.05 query with spaces
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

Then, wherever you add packages:

```nix
# ...
pkgs = with pkgs; [
  # ...
  # ...
  # ...
] ++ [
  inputs.xav-ie.packages.${pkgs.stdenv.hostPlatform.system}.zellij-tab-name-update
];
# ...
```

[..](..)
