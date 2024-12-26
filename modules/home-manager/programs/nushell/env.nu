# Nushell Environment Config File
#
# version = "0.96.1"

$env.STARSHIP_SHELL = "nu"

def get_time [] {
  date now | format date '%m/%d %I:%M'
}

def create_left_prompt [] {
  starship prompt --cmd-duration $env.CMD_DURATION_MS $'--status=($env.LAST_EXIT_CODE)'
}

def create_left_prompt_transient [] {
  create_left_prompt | str replace "\n" $"(ansi wi)(get_time)(ansi reset)\n"
}

def make_prompt_indicator [symbol]: string -> string {
  let color = if ($env.LAST_EXIT_CODE == 0) { (ansi gb) } else { (ansi rb) }
  $"(ansi reset)\b($color)($symbol)(ansi reset) "
}

$env.PROMPT_COMMAND_RIGHT = ""
# ↓ implied from ↑
# $env.TRANSIENT_PROMPT_COMMAND_RIGHT = ""

$env.PROMPT_INDICATOR = ""
# ↓ implied from ↑
# $env.TRANSIENT_PROMPT_INDICATOR = ""

$env.PROMPT_COMMAND = { || create_left_prompt }
# timestamps the prompts after running
$env.TRANSIENT_PROMPT_COMMAND = { || create_left_prompt_transient }

$env.PROMPT_INDICATOR_VI_INSERT = { || make_prompt_indicator "" }
# mantain the same prompt
$env.TRANSIENT_PROMPT_INDICATOR_VI_NORMAL = null

$env.PROMPT_INDICATOR_VI_NORMAL = { || make_prompt_indicator "" }
# mantain the same prompt
$env.TRANSIENT_PROMPT_INDICATOR_VI_INSERT = null

$env.PROMPT_MULTILINE_INDICATOR = "⟶ "
# simplify the prompts after running and remove indicators
$env.TRANSIENT_PROMPT_MULTILINE_INDICATOR = ""


# Specifies how environment variables are:
# - converted from a string to a value on Nushell startup (from_string)
# - converted from a value back to a string when running external commands
#   (to_string)
# Note: The conversions happen *after* config.nu is loaded
def from_string_simple [s] {
  $s | split row (char esep) | path expand --no-symlink
}
def to_string_simple [v] {
  $v | path expand --no-symlink | str join (char esep)
}

let SIMPLE_ENV_CONVERTER = {
  from_string: { |s| from_string_simple $s }
  to_string: { |v| to_string_simple $v }
}

# add simple env conversions here
let simple_envs = [
  "XDG_CONFIG_DIRS",
  "XDG_DATA_DIRS",
  "NIX_PATH",
  "PATH",
  "Path",
  "TERMINFO_DIRS",
];

let simple_env_conversions = $simple_envs | each { |it| {($it): $SIMPLE_ENV_CONVERTER} } | into record

$env.ENV_CONVERSIONS = $simple_env_conversions | merge {
  # add complicated env conversions here
}

# Directories to search for scripts when calling source or use
# The default for this is $nu.default-config-dir/scripts
$env.NU_LIB_DIRS = [
  # add <nushell-config-dir>/scripts
  ($nu.default-config-dir | path join 'scripts')
  # default home for nushell completions
  ($nu.data-dir | path join 'completions')
]

# Directories to search for plugin binaries when calling register
# The default for this is $nu.default-config-dir/plugins
$env.NU_PLUGIN_DIRS = [
  ($nu.current-exe | path dirname)
  # add <nushell-config-dir>/plugins
  ($nu.default-config-dir | path join 'plugins')
]

# TODO: load this from nu_scripts instead
def "from env" []: string -> record {
  lines
    | split column '#'
    | get column1
    | filter {($in | str length) > 0}
    | parse "{key}={value}"
    | update value {str trim -c '"'}
    | transpose -r -d
}

# To add entries to PATH (on Windows you might use Path), you can use the
# following pattern:
# $env.PATH = ($env.PATH | split row (char esep) | prepend '/some/path')
# An alternate way to add entries to $env.PATH is to use the
# custom command `path add` which is built into the nushell stdlib:
# use std "path add"
# $env.PATH = ($env.PATH | split row (char esep))
# path add /some/path
# path add ($env.CARGO_HOME | path join "bin")
# path add ($env.HOME | path join ".local" "bin")
# $env.PATH = ($env.PATH | uniq)

# To load from a custom file you can use:
# source ($nu.default-config-dir | path join 'custom.nu')
