#!/usr/bin/env nu

# uv tool sync script
# Default: bidirectional add-only (installs missing, adds untracked to config)
# --enforce: config wins, removes packages not in config

def main [
  --enforce  # Remove installed packages not in config
] {
  let config_path = $env.UV_TOOLS_CONFIG | path expand
  if not ($config_path | path exists) {
    print $"Config file not found: ($config_path)"
    exit 1
  }

  mut config = open $config_path

  # Get installed tools via uv tool list --show-python
  # Output format: "package-name vX.Y.Z [CPython X.Y.Z]" followed by executable lines starting with "- "
  let uv_output = uv tool list --show-python | lines | where {|line|
    not ($line | str starts-with "-") and ($line | str trim | is-not-empty)
  }
  let installed = $uv_output | each {|line|
    # Parse: "kimi-cli v1.3 [CPython 3.13.7]"
    let parts = $line | str trim | parse "{name} v{version} [{impl} {pyver}]"
    if ($parts | is-empty) {
      # Fallback for tools without python info shown
      let simple = $line | str trim | split row " "
      {
        name: $simple.0
        version: ($simple.1? | default "latest" | str replace "v" "")
        python: "3"
      }
    } else {
      let p = $parts | first
      # Extract major.minor from python version (e.g., "3.13.7]" -> "3.13")
      let pyver_clean = $p.pyver | str replace "]" "" | split row "." | first 2 | str join "."
      {
        name: $p.name
        version: $p.version
        python: $pyver_clean
      }
    }
  }
  let installed_names = $installed | get name

  let config_packages = $config | transpose name info | each {|row|
    {
      name: $row.name
      version: $row.info.version
      python: $row.info.python
    }
  }

  mut changed = false
  mut config_changed = false

  # Install missing packages (config → installed)
  for pkg in $config_packages {
    if $pkg.name not-in $installed_names {
      print $"Installing: ($pkg.name)==($pkg.version) with Python ($pkg.python)"
      uv tool install $"($pkg.name)==($pkg.version)" --python $pkg.python
      $changed = true
    }
  }

  if $enforce {
    # Remove extras (config wins)
    let config_names = $config_packages | get name
    let extras = $installed | where {|row| $row.name not-in $config_names }

    if ($extras | length) > 0 {
      print "Will remove the following:\n"
      for pkg in $extras {
        print $"  ($pkg.name)@($pkg.version) [Python ($pkg.python)]"
      }
      print ""

      let confirm = input "Proceed? [y/N] " | str trim | str downcase
      if $confirm != "y" {
        print "Aborted."
        return
      }

      for pkg in $extras {
        print $"Removing: ($pkg.name)"
        uv tool uninstall $pkg.name
        $changed = true
      }
    }
  } else {
    # Add extras to config (installed → config)
    let config_names = $config_packages | get name
    let extras = $installed | where {|row| $row.name not-in $config_names }

    for pkg in $extras {
      print $"Adding to config: ($pkg.name)@($pkg.version) [Python ($pkg.python)]"
      $config = $config | insert $pkg.name { version: $pkg.version, python: $pkg.python }
      $config_changed = true
    }

    # Always save to normalize formatting
    $config | to json --indent 2 | save -f $config_path
    "\n" | save --append $config_path

    if $config_changed {
      print $"\nUpdated ($config_path)"
    }
  }

  if $changed {
    print "\nSync complete."
  } else if not $config_changed {
    print "All packages in sync."
  }
}
