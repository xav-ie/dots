copy-on-select = true
quit-after-last-window-closed = true
macos-option-as-alt = true
macos-titlebar-style = hidden
window-decoration = false
title =" "

# Automatically install terminfo on remote SSH hosts and preserve TERM in sudo
shell-integration-features = ssh-terminfo,sudo

cursor-style-blink = false
background-opacity = 1.0
background-blur-radius = 0
theme = light:XLight,dark:XDark

# I use zellij for maximum portability, so I don't want to depend on
# Ghostty window management primitives.
keybind = ctrl+shift+e=unbind
keybind = ctrl+shift+n=unbind
keybind = ctrl+shift+o=unbind
keybind = ctrl+shift+t=unbind
keybind = ctrl+comma=unbind
keybind = ctrl+plus=increase_font_size:1
keybind = ctrl+minus=decrease_font_size:1

config-file = ~/.config/ghostty/config-nix
