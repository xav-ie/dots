# Nushell Environment Config File
#
# version = "0.96.1"

$env.STARSHIP_SHELL = "nu"
$env.SHELL = "nu"
$env.TERM = "xterm-256color"

def get_time []: nothing -> string {
  # date now | format date '%m/%d %I:%M%p'
  date now | format date '%m/%d %H:%M'
}

def create_left_prompt []: nothing -> string {
  starship prompt --cmd-duration $env.CMD_DURATION_MS $'--status=($env.LAST_EXIT_CODE)'
}

def create_left_prompt_transient []: nothing -> string {
  create_left_prompt | str replace "\n" $"(ansi wi)(get_time)(ansi reset)\n"
}

def make_prompt_indicator [symbol]: string -> string {
  let color = if ($env.LAST_EXIT_CODE == 0) { (ansi gb) } else { (ansi rb) }
  $"(ansi reset)($color)($symbol)(ansi reset) "
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
# TODO: should I even be path expanding?
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

# Path expansion brakes some envs
def from_string_simpler [s] {
  $s | split row (char esep)
}
def to_string_simpler [v] {
  $v | str join (char esep)
}
let SIMPLER_ENV_CONVERTER = {
  from_string: { |s| from_string_simpler $s }
  to_string: { |v| to_string_simpler $v }
}

# add simple env conversions here
let simple_envs = [
  "XDG_CONFIG_DIRS",
  "XDG_DATA_DIRS",
  "PATH",
  "Path",
  "TERMINFO_DIRS",
];

let simpler_envs = [
  "NIX_PATH"
]

let simple_env_conversions = $simple_envs
                             | each { |it| {($it): $SIMPLE_ENV_CONVERTER} }
                             | into record
let simpler_env_conversions = $simpler_envs
                              | each { |it| {($it): $SIMPLER_ENV_CONVERTER} }
                              | into record

$env.ENV_CONVERSIONS = $simple_env_conversions
                       | merge $simpler_env_conversions
                       | merge {
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
    | update value {
        str trim -c '"' |
        str replace -a "\\n" "\n"
    }
    | transpose -r -d
}

# def atan2 [y x] {
#   let pi = 4 * (1 | math arctan)
#   if $x > 0 {
#     ($y / $x) | math arctan
#   } else if $x < 0 and $y >= 0 {
#     (($y / $x) | math arctan) + $pi
#   } else if $x < 0 and $y < 0 {
#     (($y / $x) | math arctan) - $pi
#   } else if $x == 0 and $y > 0 {
#     $pi / 2
#   } else if $x == 0 and $y < 0 {
#     -1 * $pi / 2
#   } else {
#     0
#   }
# }

# parses a record or string int a float record
# i.e.
# - parse_color "rgb(255,255,255)" -> record<r: float, g: float, b: float>
# - parse_color {r: 255, g: 255, b: 255} -> record<r: float, g: float, b: float>
# - parse_color 'hsl(260, 70%, 50%)' -> record<h: float, s: float, l: float>
# - parse_color {h: 260, s: 70, l: 50} -> record<h: float, s: float, l: float>
# - parse_color 'xyz(0.5, 0.5, 0.5)' -> record<x: float, y: float, z: float>
def parse_color [input]: [
    any -> any
    # -> `record<$a: float, $b: float, $c: float>` or `nothing` but nu
    # does not yet support multiple return types or generics
  ] {
    if ($input | describe) == "string" {
      let prefix = $input | str substring 0..2 | split chars
      let suffix = $input | str substring 3..
      let parsed = ($suffix
        | str replace -a "%" ""
        | str replace "deg" ""
        | parse "({a},{b},{c})"
        | first
        | items {|key, val| {$key: ($val | into float)}}
        | reduce {|it| merge $it})

      # rename the keys with the prefix
      return (($parsed | transpose)
              | zip $prefix
              | each {|row| {
                              key: $row.1, value: $row.0.column1
                            }
                }
              | transpose -rd)

    # assert that it is either
    # - record<r: int, g: int, b: int>
    # - record<r: float, g: float, b: float>
    # or mix of both floats and ints inside
    } else if ($input
        | describe
        | parse "record<{a_key}: {a_type}, {b_key}: {b_type}, {c_key}: {c_type}>"
        | transpose key val
        | where {|| $in.key =~ "_type$" }
        | all {|| $in.val == "int" or $in.val == "float"}) {
      return ($input
        | items {|key, val| {$key: ($val | into float)}}
        | reduce {|it| merge $it})
    } else {
      # TODO: throw error?
    }
}

# parses and normalizes an hsl color
def parse_hsl [input]: [
    any -> any # `record<h: float, s: float, l: float>` or `nothing` but nu does
               # not yet support multiple return types
  ] {
  let parsed = parse_color $input
  # normalize s and l since their standard form is [0, 1]
  let result = ($parsed
    | items {|key, value|
      if $key != 'h' {
        { $key: ($value / 100.0) }
      } else {
        { $key: $value }
      }}
    | reduce {|it| merge $it})

  $result
}

# parses and normalizes an hsl color
def parse_rgb [input]: [
    any -> any # `record<h: float, s: float, l: float>` or `nothing` but nu does
               # not yet support multiple return types
  ] {
  let parsed = parse_color $input

  # do not normalize, rgb's standard form is [0, 255]
  $parsed
}

# rgb(r,g,b) string or record<r: float, g: float, b: float> -> binary hex
# convert to string via `| encode hex`
def rgb_to_hex []  {
  # must be of type any
  each {|$input: any| # -> binary
    let parsed = parse_color $input

    let result = ($parsed
    | transpose key val
    | each {|| $in.val
      | math round
      | into binary --compact
      | encode hex
      | into string
    }
    | str join
    | decode hex)
    $result
  }
}

def hex_to_rgb [] {
  each {|line|
    if $line =~ "^#?([0-9a-fA-F]{6})" {
      # Extract the hex color code (without '#')
      let hex = $line | str replace -r "^#" ""

      # Convert the hex to RGB components
      let r = ($hex | str substring 0..1 | decode hex | into int)
      let g = ($hex | str substring 2..3 | decode hex | into int)
      let b = ($hex | str substring 4..5 | decode hex | into int)

      {r: $r, g: $g, b: $b}
    }
  }
}

# convert an rgb color to hsl
# i.e.
# - rgb_to_hsl "rgb(255,255,255)" -> record<h: float, s: float, l: float>
# - rgb_to_hsl {r: 255, g: 255, b: 255} -> record<h: float, s: float, l: float>
def rgb_to_hsl [] {
  each {|input|
    # normalize the rgb values
    let parsed = ((parse_rgb $input)
      | items {|key, value| { $key: ($value / 255.0) }}
      | reduce {|it| merge $it})
    let r = $parsed.r
    let g = $parsed.g
    let b = $parsed.b
    # Calculate HSL
    let max = [$r $g $b] | math max
    let min = [$r $g $b] | math min
    let chroma = $max - $min;

    # Calculate hue (hp)
    let hp = if $chroma == 0 {
      0.0
    } else if $max == $r {
      (($g - $b) / $chroma) mod 6
    } else if $max == $g {
      (($b - $r) / $chroma) + 2.0
    } else {
      (($r - $g) / $chroma) + 4.0
    }

    let h = ($hp * 60) mod 360

    # there are several methods to calculate lightness
    # we are using the mid-range value
    # 3. Mid-range value === Lightness
    let mid_range_value = ($max + $min) / 2
    # mid_range_value seems the most accurate the other ones
    # add unneccessary weight and work to the calculations to revert
    let l = $mid_range_value

    # there are three methods to calculate saturation
    # 2. saturation_lightness === Saturation
    let saturation_lightness = if $l == 0 or $l == 1 {
      0.0
    } else {
      $chroma / (1 - (2 * $l - 1 | math abs))
    }
    let s = $saturation_lightness #value

    let result = ({h: $h, s: $s, l: $l}
      | items {|key, value|
        if $key != 'h' {
          { $key: ($value * 100.0 | math round) }
        } else {
          { $key: ($value | math round) }
        }}
      | reduce {|it| merge $it})
    $result
  }
}

# convert an hsl color to rgb
# i.e.
# - hsl_to_rgb "hsl(260, 70%, 50%)" -> record<r: float, g: float, b: float>
# - hsl_to_rgb {h: 260, s: 70, l: 50} -> record<r: float, g: float, b: float>
def hsl_to_rgb [] {
  each {|line|
    let $parsed = parse_hsl $line
    # Extract HSL values
    let h = $parsed.h
    let s = $parsed.s
    let l = $parsed.l

    # Calculate chroma (c)
    let chroma = (1 - (2 * $l - 1 | math abs)) * $s
    # Calculate x
    let hp = $h / 60.0
    let x = $chroma * (1 - ($hp mod 2 - 1 | math abs))
    # Calculate m
    let m = $l - $chroma / 2

    # Calculate rp, gp, bp based on the hue
    let rpgpbp = if $hp < 1 {
      [$chroma, $x, 0]
    } else if $hp < 2 {
      [$x, $chroma, 0]
    } else if $hp < 3 {
      [0, $chroma, $x]
    } else if $hp < 4 {
      [0, $x, $chroma]
    } else if $hp < 5 {
      [$x, 0, $chroma]
    } else {
      [$chroma, 0, $x]
    }

    let rp = $rpgpbp | get 0
    let gp = $rpgpbp | get 1
    let bp = $rpgpbp | get 2

    # Add m to each component to shift back to normal range
    let r = (($rp + $m) * 255) | math round
    let g = (($gp + $m) * 255) | math round
    let b = (($bp + $m) * 255) | math round

    {r: $r, g: $g, b: $b}
  }
}

try { open ~/.env | load-env }
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
