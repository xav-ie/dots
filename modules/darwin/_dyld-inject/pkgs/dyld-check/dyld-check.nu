# dyld-check: report dyld-injection-related issues since the last
# darwin-rebuild activation.
#
# Three sections:
#
#   1. env var sanity. Does the runtime DYLD_INSERT_LIBRARIES match
#      what the dyld-inject agent's plist tells launchd to set, and do
#      all the configured paths actually exist on disk.
#
#   2. crashes since rebuild, grouped by process. Flags any whose .ips
#      report mentions one of our injected dylibs by basename, since
#      that is the strongest signal a crash was caused by injection.
#
#   3. dyld and AMFI error log entries since rebuild. Surfaces things
#      like AMFI silently stripping DYLD_INSERT_LIBRARIES from
#      hardened-runtime apps when amfi_get_out_of_my_way=1 is missing.

const AGENT_PLIST = "~/Library/LaunchAgents/org.nix-community.home.dyld-inject.plist"
const CRASH_DIR = "~/Library/Logs/DiagnosticReports"

def header [msg: string] {
  print $"(ansi cyan)==>(ansi reset) ($msg)"
}

def ok [msg: string] { print $"   (ansi green)ok:(ansi reset) ($msg)" }
def warn [msg: string] { print $"   (ansi yellow)warning:(ansi reset) ($msg)" }
def fail [msg: string] { print $"   (ansi red)fail:(ansi reset) ($msg)" }
def info [msg: string] { print $"   ($msg)" }

# BSD stat by absolute path — nuenv's PATH may have GNU coreutils ahead
# of /usr/bin, and `stat -f` is BSD-only syntax.
def bsd_stat_mtime [path: string] {
  ^/usr/bin/stat -f '%Sm' -t '%Y-%m-%dT%H:%M:%S' $path | str trim | into datetime
}

# mtime of /run/current-system symlink = last nix-darwin activation.
def get_rebuild_time [] { bsd_stat_mtime "/run/current-system" }

# stat-based mtime of any file; used to filter crash reports.
def file_mtime [path: string] { bsd_stat_mtime $path }

# Read DYLD_INSERT_LIBRARIES value from the dyld-inject agent's plist.
# Returns null if the plist does not exist or has unexpected shape.
def get_configured_value [] {
  let path = $AGENT_PLIST | path expand
  if not ($path | path exists) {
    return null
  }
  let json = (^plutil -convert json -o - $path | from json)
  let args = $json | get --optional ProgramArguments
  if $args == null { return null }
  if ($args | length) < 4 { return null }
  if $args.0 != "/bin/launchctl" { return null }
  if $args.1 != "setenv" { return null }
  if $args.2 != "DYLD_INSERT_LIBRARIES" { return null }
  $args.3
}

def get_runtime_value [] {
  let v = (^launchctl getenv DYLD_INSERT_LIBRARIES | str trim)
  if ($v | is-empty) { null } else { $v }
}

# Section 1: env var sanity. Returns the configured paths list (or null)
# so later sections can derive the dylib-name allowlist for stack matching.
def section_env_sanity [] {
  header "1. env var sanity"

  let configured = (get_configured_value)
  let runtime = (get_runtime_value)

  if $configured == null {
    warn "no dyld-inject agent plist on disk; either services.dyldInject.libraries is empty or this is not a nix-darwin host"
    return null
  }

  let paths = $configured | split row ":"
  let n = $paths | length
  info $"configured: ($n) librar(if $n == 1 { 'y' } else { 'ies' })"
  for p in $paths {
    info $"  - ($p)"
  }
  print ""

  if $runtime == null {
    fail "runtime DYLD_INSERT_LIBRARIES is empty; agent did not run, was unsetenv'd, or you have not logged in since activation"
  } else if $runtime == $configured {
    ok "runtime DYLD_INSERT_LIBRARIES matches configured value"
  } else {
    fail "runtime DYLD_INSERT_LIBRARIES differs from configured plist value (out-of-band setenv/unsetenv changed it)"
    info $"runtime: ($runtime)"
  }
  print ""

  for p in $paths {
    if ($p | path exists) {
      ok $"present: ($p | path basename)"
    } else {
      fail $"MISSING: ($p)"
    }
  }

  $paths
}

# True if any of the given names appears anywhere in a crash file.
# Crash reports are JSON-with-header text files; substring match is
# sufficient to catch loaded-images and stack-frame references.
def crash_mentions_names [crash_path: string, names: list<string>] {
  for n in $names {
    let r = (^/usr/bin/grep -q -- $n $crash_path | complete)
    if $r.exit_code == 0 { return true }
  }
  false
}

def section_crashes [rebuild_time: datetime, configured_paths] {
  header "2. crashes since rebuild"

  let dir = $CRASH_DIR | path expand
  if not ($dir | path exists) {
    warn $"crash dir not found: ($dir)"
    return
  }

  let all = (glob $"($dir)/*.ips")
  let total = $all | length
  let crashes = (
    $all
    | each { |p|
        let m = (file_mtime $p)
        if $m >= $rebuild_time { { path: $p, modified: $m } } else { null }
      }
    | compact
  )

  if ($crashes | is-empty) {
    ok $"no crashes since rebuild [($total) total in archive]"
    return
  }

  let dylib_names = (
    if $configured_paths == null { [] }
    else { $configured_paths | each {|p| $p | path basename | str replace -r '\.dylib$' '' } }
  )

  let by_process = (
    $crashes
    | insert process_name { |r|
        $r.path | path basename | str replace -r '-\d{4}-\d{2}-\d{2}.*$' ''
      }
    | insert injected_dylib { |r|
        if ($dylib_names | is-empty) { false }
        else { crash_mentions_names $r.path $dylib_names }
      }
    | group-by process_name
    | transpose process records
    | each { |r|
        {
          process: $r.process,
          count: ($r.records | length),
          latest: ($r.records | get modified | sort | last | format date '%Y-%m-%d %H:%M'),
          injected_dylib_in_stack: ($r.records | any {|x| $x.injected_dylib })
        }
      }
    | sort-by count --reverse
  )

  print ($by_process | table)

  let suspicious = $by_process | where injected_dylib_in_stack
  if not ($suspicious | is-empty) {
    print ""
    fail "injected dylib appears in the stack of:"
    for s in $suspicious {
      info $"  - ($s.process): ($s.count) crashes"
    }
    info "this is the strongest signal a crash was caused by injection."
  }
}

def section_dyld_errors [rebuild_time: datetime] {
  header "3. dyld / AMFI errors in system log"

  let start_str = $rebuild_time | format date '%Y-%m-%d %H:%M:%S'
  # Only Error/Fault messages — without this filter, every `log show`
  # invocation that mentions "DYLD_INSERT_LIBRARIES" in its own argv
  # shows up as a self-referential match.
  let predicate = '
    (eventMessage CONTAINS[c] "DYLD_INSERT_LIBRARIES" AND (messageType == "Error" OR messageType == "Fault"))
    OR (eventMessage CONTAINS[c] "amfi" AND (messageType == "Error" OR messageType == "Fault"))
    OR (subsystem == "com.apple.dyld" AND (messageType == "Error" OR messageType == "Fault"))
  '

  let r = (
    ^/usr/bin/log show --start $start_str --style ndjson --predicate $predicate
    | complete
  )

  if $r.exit_code != 0 {
    fail $"log show failed [exit code ($r.exit_code)]"
    if ($r.stderr | str length) > 0 {
      info $r.stderr
    }
    return
  }

  # Filter the parsed entries:
  #   - drop trailing metadata records like {"count":N,"finished":1}
  #     which don't have eventMessage
  #   - drop self-references from /usr/bin/log itself (this script
  #     invokes log show, which shows up in the log)
  let entries = (
    $r.stdout
    | lines
    | each {|l| try { $l | from json } catch { null } }
    | compact
    | where { |e|
        let cols = try { $e | columns } catch { [] }
        if not ("eventMessage" in $cols) { return false }
        let proc = $e | get --optional processImagePath | default ''
        not ($proc | str ends-with "/log")
      }
  )

  if ($entries | is-empty) {
    ok "no dyld / AMFI error entries in log since rebuild"
    return
  }

  let summary = (
    $entries
    | each { |e|
        {
          ts: ($e | get --optional timestamp | default '?' | str substring 0..19),
          process: ($e | get --optional processImagePath | default '?' | path basename),
          message: ($e | get --optional eventMessage | default '' | str substring 0..120)
        }
      }
    | first 30
  )
  print ($summary | table)

  let n = $entries | length
  if $n > 30 {
    info $"... and ($n - 30) more entries; rerun `log show` directly to see all"
  }
}

def main [] {
  let rebuild_time = (get_rebuild_time)
  let ts = $rebuild_time | format date '%Y-%m-%d %H:%M:%S'
  print ""
  print $"(ansi cyan)dyld-check(ansi reset)  last rebuild: (ansi yellow)($ts)(ansi reset)"
  print ""

  let paths = (section_env_sanity)
  print ""
  section_crashes $rebuild_time $paths
  print ""
  section_dyld_errors $rebuild_time
  print ""
}
