# Nushell Config File
#
# config.nu is commonly used to:
# - Set environment variables for Nushell and other applications
# - Set Nushell settings in $env.config
# - Load modules or source files so that their commands are readily available
# - Run any other applications or commands at startup
#
# version = "0.96.1"

$env.config.color_config.search_result = { bg: "#dd2200" fg: white }

let carapace_completer = {|spans|
  carapace $spans.0 nushell ...$spans | from json
}
$env.config.completions.external = {
  # set to false to prevent nushell looking into $env.PATH to find more
  # suggestions, `false` recommended for WSL users as this look up may be
  # very slow
  enable: true
  # setting it lower can improve completion performance at the cost of
  # omitting some options
  max_results: 100
  completer: $carapace_completer
}

$env.config.cursor_shape = {
  # block, underscore, line, blink_block, blink_underscore, blink_line,
  # inherit to skip setting cursor shape (line is the default)
  emacs: line
  # block, underscore, line, blink_block, blink_underscore, blink_line,
  # inherit to skip setting cursor shape (block is the default)
  vi_insert: line
  # block, underscore, line, blink_block, blink_underscore, blink_line,
  # inherit to skip setting cursor shape (underscore is the default)
  vi_normal: blink_block
}

$env.config.edit_mode = "vi" # emacs, vi

$env.config.explore = {
  status_bar_background: { fg: white, bg: black },
  command_bar_text: { fg: "#C4C9C6" },
  highlight: { fg: "black", bg: "yellow" },
  status: {
    error: { fg: "white", bg: "red" },
    warn: {}
    info: {}
  },
  selected_cell: { bg: light_blue },
}

$env.config.hooks.pre_prompt = [
  { || zellij-tab-name-update }
]

$env.config.keybindings ++= [
  {
    name: cut_line_from_start
    modifier: control
    keycode: char_u
    mode: [emacs, vi_insert]
    event: { edit: cutfromstart }
  }
]

# true or false to enable or disable right prompt to be rendered on last line
# of the prompt.
$env.config.render_right_prompt_on_last_line = false

$env.config.show_banner = false

$env.config.plugin_gc.plugins = {
  gstat: {
    enabled: true
  }
}

$env.config.table = {
  # basic, compact, compact_double, light, thin, with_love, rounded,
  # reinforced, heavy, none, other
  mode: compact
  # "always" show indexes, "never" show indexes, "auto" = show indexes when a
  # table has "index" column
  index_mode: always
  # show 'empty list' and 'empty record' placeholders for command output
  show_empty: true
  # a left right padding of each column in a table
  padding: { left: 1, right: 1 }
  trim: {
    # wrapping or truncating
    methodology: wrapping
    # A strategy used by the 'wrapping' methodology
    wrapping_try_keep_words: true
    # A suffix used by the 'truncating' methodology
    truncating_suffix: "..."
  }
  # show header text on separator/border line
  header_on_separator: false
  # # limit data rows from top and bottom after reaching a set point
  # abbreviated_row_count: 10
}
