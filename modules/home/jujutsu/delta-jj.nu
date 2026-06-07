#!/usr/bin/env -S nu --stdin

def --wrapped main [...args] {
  # #200030
  let section_bg = $"(ansi -e '48;2;32;0;48m')"
  delta --width (term size | get columns) ...$args
  | lines
  | par-each -k {|line|
    if ("Δ" in ($line | ansi strip)) {
      $"($section_bg)($line)(ansi reset)"
    } else {
      $line
    }
  }
  | str join "\n"
}
