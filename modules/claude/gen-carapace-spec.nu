#!/usr/bin/env nu
# Reads `claude --help` on stdin, emits a carapace command spec (YAML) on stdout.
# Pure text transform — no claude execution here (the build runs --help and pipes in).

# Group help lines into entries: a new entry starts at a line matching `start`
# (e.g. `^  -` for options, `^  \S` for commands); deeper-indented lines are
# continuations of the previous entry's description.
def group-entries [start: string] {
  reduce --fold [] {|line, acc|
    if ($line =~ $start) {
      $acc | append [[$line]]
    } else if ($acc | is-empty) {
      $acc
    } else {
      $acc | update (($acc | length) - 1) {|entry| $entry | append $line }
    }
  }
}

def main [helpFile: string] {
  let lines = (open --raw $helpFile | lines)
  let idx = {
    opt: ($lines | enumerate | where item == "Options:" | get index.0? | default 0)
    cmd: ($lines | enumerate | where item == "Commands:" | get index.0? | default ($lines | length))
  }
  let descIdx = ($lines | enumerate | where {|x| $x.item =~ '^Claude Code'} | get index.0? | default (-1))
  let prog = (if $descIdx >= 0 {
    $lines | slice $descIdx.. | take while {|l| $l | str trim | is-not-empty } | each {|l| $l | str trim} | str join ' '
  } else { "Claude Code CLI" })

  # ---- options -> flags{} + completion.flag{} ----
  let optLines = ($lines | slice ($idx.opt + 1)..<$idx.cmd | where {|l| $l | str trim | is-not-empty })
  let opts = ($optLines | group-entries '^  -' | each {|e|
    let first = ($e | get 0 | str trim)
    let flagspec = ($first | str replace --regex '\s{2,}.*$' '')
    let inline = (if ($first =~ '\s{2,}') { $first | str replace --regex '^.*?\s{2,}' '' } else { '' })
    let cont = ($e | skip 1 | each {|l| $l | str trim} | str join ' ')
    let desc = ([$inline $cont] | where {|x| $x | is-not-empty } | str join ' ' | str trim)

    let longs = ($flagspec | parse --regex '(?<m>--[\w-]+)' | get m)
    let shorts = ($flagspec | parse --regex '(?:^|[\s,])(?<s>-[a-zA-Z])(?:[\s,]|$)' | get s)
    let hasValue = ($flagspec =~ '[<\[]')
    let repeat = ($flagspec =~ '\.\.\.')
    let long = ($longs | get 0? | default $flagspec)
    let suffix = (if $repeat and $hasValue { '=*' } else if $hasValue { '=' } else { '' })
    let key = (if ($shorts | is-empty) { $"($long)($suffix)" } else { $"($shorts | get 0), ($long)($suffix)" })
    let choices = ($desc
      | parse --regex '\(choices:\s*(?<c>[^)]+)\)' | get c?.0? | default ''
      | parse --regex '"(?<v>[^"]+)"' | get v | uniq)
    { key: $key, name: ($long | str replace --all '-' '-' | str trim --char '-'), desc: $desc, choices: $choices }
  })

  let flags = ($opts | reduce --fold {} {|o, acc| $acc | insert $o.key $o.desc })
  let flagCompletions = ($opts | where {|o| $o.choices | is-not-empty }
    | reduce --fold {} {|o, acc| $acc | insert ($o.name) $o.choices })

  # ---- commands ----
  let cmdLines = ($lines | slice ($idx.cmd + 1).. | where {|l| $l | str trim | is-not-empty })
  let commands = ($cmdLines | group-entries '^  \S' | each {|e|
    let first = ($e | get 0 | str trim)
    let namepart = ($first | str replace --regex '\s{2,}.*$' '')
    let desc = (if ($first =~ '\s{2,}') { $first | str replace --regex '^.*?\s{2,}' '' } else { '' })
    let cont = ($e | skip 1 | each {|l| $l | str trim} | str join ' ')
    let fullDesc = ([$desc $cont] | where {|x| $x | is-not-empty } | str join ' ' | str trim)
    let names = ($namepart | str replace --regex '\s.*$' '' | split row '|')
    { name: ($names | get 0), aliases: ($names | skip 1), description: $fullDesc }
  } | where {|c| $c.name != "help" })

  let spec = {
    name: "claude"
    description: $prog
    flags: $flags
    completion: { flag: $flagCompletions }
    commands: ($commands | each {|c|
      if ($c.aliases | is-empty) {
        { name: $c.name, description: $c.description }
      } else {
        { name: $c.name, aliases: $c.aliases, description: $c.description }
      }
    })
  }
  $"# yaml-language-server: $schema=https://carapace.sh/schemas/command.json\n($spec | to yaml)"
}
