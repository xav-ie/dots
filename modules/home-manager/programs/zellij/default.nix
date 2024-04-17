{ inputs, outputs, pkgs, ... }:
let
  default_tab_template = ''
    default_tab_template {
        children
        pane size=1 borderless=true {
            plugin location="file:${pkgs.zjstatus}/bin/zjstatus.wasm" {
              format_left             "{mode} #[fg=#FA89B4,bold]{session} {tabs}"
              format_right            "{command_pomo}{datetime}"
              format_space            ""
              border_enabled          "false"
              mode_normal             "#[bg=magenta] "
              mode_locked             "#[bg=black] {name} "
              mode_locked             "#[bg=black] {name} "
              mode_resize             "#[bg=black] {name} "
              mode_pane               "#[bg=black] {name} "
              mode_tab                "#[bg=black] {name} "
              mode_scroll             "#[bg=black] {name} "
              mode_enter_search       "#[bg=black] {name} "
              mode_search             "#[bg=black] {name} "
              mode_rename_tab         "#[bg=black] {name} "
              mode_rename_pane        "#[bg=black] {name} "
              mode_session            "#[bg=black] {name} "
              mode_move               "#[bg=black] {name} "
              mode_prompt             "#[bg=black] {name} "
              mode_tmux               "#[bg=red] {name} "
              tab_normal              "#[fg=#6C7086] {name} "
              tab_active              "#[fg=magenta,bold,italic] {name} "

              datetime                "#[fg=cyan,bold] {format}"
              datetime_format         "%m/%d %I:%M"
              datetime_timezone       "America/New_York"
              command_pomo_command    "uairctl fetch '{state} {time}'"
              command_pomo_format     "#[fg=blue] {stdout}"
              command_pomo_interval   "1"
              command_pomo_rendermode "static"
            }
        }
    }
  '';
in {
  programs = { zellij = { enable = true; }; };
  home.file.".config/zellij/config.kdl".source =
    ../../dotfiles/zellij/config.kdl;
  home.file.".config/zellij/layouts/default.kdl".text = ''
    layout {
        ${default_tab_template}
        tab
    }
  '';
}
