#!/usr/bin/env nu

# Claude Code plugin setup script
# Marketplaces are managed by Nix (pinned flake inputs)
# This script only handles plugin installation
# Default: bidirectional add-only (installs missing, updates config with extras)
# --enforce: config wins, removes plugins not in config

def main [
  --enforce  # Remove installed plugins not in config
] {
  let config_path = $env.CLAUDE_PLUGINS_CONFIG | path expand
  if not ($config_path | path exists) {
    print $"Config file not found: ($config_path)"
    exit 1
  }

  mut config = open $config_path
  let plugins_dir = "~/.claude/plugins" | path expand
  let config_plugins = $config.plugins

  # Get installed plugins
  let installed_file = $plugins_dir | path join "installed_plugins.json"
  let installed_plugins = if ($installed_file | path exists) {
    open $installed_file | get plugins | columns
  } else {
    []
  }

  mut changed = false
  mut config_changed = false

  # Install missing plugins (config → installed)
  for plugin in $config_plugins {
    if $plugin not-in $installed_plugins {
      print $"Installing plugin: ($plugin)"
      try { claude plugin install $plugin; $changed = true }
    }
  }

  if $enforce {
    # Remove extras (config wins)
    let extra_plugins = $installed_plugins | where {|p| $p not-in $config_plugins }

    if ($extra_plugins | length) > 0 {
      print "Will remove the following:\n"
      for p in $extra_plugins {
        print $"  plugin: ($p)"
      }
      print ""

      let confirm = input "Proceed? [y/N] " | str trim | str downcase
      if $confirm != "y" {
        print "Aborted."
        return
      }

      for p in $extra_plugins {
        print $"Uninstalling plugin: ($p)"
        let result = do { claude plugin uninstall $p } | complete
        if $result.exit_code != 0 {
          # Fallback: remove directly from JSON if Claude can't uninstall (orphaned plugin)
          print $"  Claude uninstall failed, removing from JSON directly"
          let installed_data = open $installed_file
          let updated = $installed_data | update plugins { reject $p }
          $updated | save -f $installed_file
        }
        $changed = true
      }
    }
  } else {
    # Add extras to config (installed → config)
    let extra_plugins = $installed_plugins | where {|p| $p not-in $config_plugins }
    for p in $extra_plugins {
      print $"Adding to config: ($p)"
      $config = $config | upsert plugins {|c| $c.plugins | append $p }
      $config_changed = true
    }

    # Always save to normalize formatting (trailing newline, indentation)
    $config | to json --indent 2 | save -f $config_path
    "\n" | save --append $config_path

    if $config_changed {
      print $"\nUpdated ($config_path)"
    }
  }

  if $changed {
    print "\nChanges made. Restart Claude Code to apply."
  } else if not $config_changed {
    print "All plugins in sync."
  }
}
