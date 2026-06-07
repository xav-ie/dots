#!/usr/bin/env nu

# Wait for default audio source to be available, then start noisetorch
def main [] {
  print "Starting noisetorch-init..."
  for i in 1..60 {
    print $"Attempt ($i): checking for default source..."
    let result = do { pactl get-default-source } | complete
    let source = $result.stdout | str trim
    print $"  exit_code: ($result.exit_code), stdout: '($source)'"
    # Check that we got an actual device, not the @DEFAULT_SOURCE@ placeholder
    if $result.exit_code == 0 and ($source | is-not-empty) and $source != "@DEFAULT_SOURCE@" {
      print $"  Found source, starting noisetorch..."
      run-external "/run/wrappers/bin/noisetorch" "-i"
      return
    }
    print $"  No source yet, sleeping 1s..."
    sleep 1sec
  }
  print "Timed out waiting for default audio source"
  exit 1
}
