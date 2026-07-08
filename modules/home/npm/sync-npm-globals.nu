#!/usr/bin/env nu

# npm global package sync script
# Default: bidirectional add-only (installs missing, adds untracked to config)
# --enforce: config wins, removes packages not in config

def main [
  --enforce  # Remove installed packages not in config
] {
  let config_path = $env.NPM_GLOBALS_CONFIG | path expand
  if not ($config_path | path exists) {
    print $"Config file not found: ($config_path)"
    exit 1
  }

  mut config = open $config_path

  # Get installed global packages via filesystem (faster than npm list)
  let npm_prefix = (npm config get prefix | str trim)
  let node_modules = $npm_prefix | path join "lib" | path join "node_modules"
  let installed = if ($node_modules | path exists) {
    # Handle both scoped (@org/pkg) and regular packages
    ls $node_modules | where type == dir | each {|d|
      let dir_name = $d.name | path basename
      if ($dir_name | str starts-with "@") {
        # Scoped package - list subdirs
        ls $d.name | where type == dir | each {|sub|
          let pkg_json = $sub.name | path join "package.json"
          if ($pkg_json | path exists) {
            let pkg = open $pkg_json
            { name: $pkg.name, version: $pkg.version }
          }
        }
      } else {
        # Regular package
        let pkg_json = $d.name | path join "package.json"
        if ($pkg_json | path exists) {
          let pkg = open $pkg_json
          { name: $pkg.name, version: $pkg.version }
        }
      }
    } | flatten | compact
  } else {
    []
  }
  let installed_names = $installed | get name

  let config_packages = $config | transpose name version

  mut changed = false
  mut config_changed = false

  # Install missing packages (config → installed)
  for pkg in $config_packages {
    if $pkg.name not-in $installed_names {
      print $"Installing: ($pkg.name)@($pkg.version)"
      npm install -g $"($pkg.name)@($pkg.version)"
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
        print $"  ($pkg.name)@($pkg.version)"
      }
      print ""

      let confirm = input "Proceed? [y/N] " | str trim | str downcase
      if $confirm != "y" {
        print "Aborted."
        return
      }

      for pkg in $extras {
        print $"Removing: ($pkg.name)"
        npm uninstall -g $pkg.name
        $changed = true
      }
    }
  } else {
    # Add extras to config (installed → config)
    let config_names = $config_packages | get name
    let extras = $installed | where {|row| $row.name not-in $config_names }

    for pkg in $extras {
      print $"Adding to config: ($pkg.name)@($pkg.version)"
      $config = $config | insert $pkg.name $pkg.version
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
