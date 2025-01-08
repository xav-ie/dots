# home-manager

Home Manager is an amazing tool for configuring your systems. Generally,
these configurations are portable and easy-to-use. They come with
convenient nixified knobs to configure programs you want installed and
it is simple to escape into raw config when necessary.

You can find out more about Home Manager on [their homepage](https://nix-community.github.io/home-manager/).

Instead of reading through the giant manual, I highly recommend [Home Manager
Option Search](https://home-manager-options.extranix.com/) when you are trying to find options.

```mermaid
---
config:
  theme: base
  themeVariables:
    darkMode: true
    primaryColor: "#1a0020"
    primaryTextColor: "#fa99fa"
    primaryBorderColor: "#aaaafa"
    lineColor: "#888"
    fontFamily: "monospace"
---
classDiagram
    home-manager: hm modules and setup for linux and mac
    default: general modules
    programs: program modules
    linux: linux specific modules
    mac: mac specific modules
    home-manager <-- default
    home-manager .. programs
    home-manager <-- linux
    home-manager <-- mac
```

<div align="center">
    <em>My Home Manager Layout</em>
</div>

[..](..)
