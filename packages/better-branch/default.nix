{
  writeNuApplication,
  git,
}:
writeNuApplication {
  name = "better-branch";
  runtimeInputs = [
    git
  ];
  text = # nu
    ''
      def main [] {
        # Get branches with commit dates in unix timestamp for accurate sorting
        let branches = (git for-each-ref --count=10 --sort=-committerdate
          --format="%(refname:short)|%(upstream:short)|%(committerdate:relative)|%(committerdate:unix)" refs/heads/
          | lines
          | par-each { |line| $line | split row "|" }
          | par-each { |cols| {
            branch: ($cols | get 0),
            upstream: ($cols | get 1),
            time: ($cols | get 2),
            timestamp: ($cols | get 3 | into int)
          }})

        # TODO: do in background and print status after nushell update to 0.103.0
        git fetch --quiet --all

        let branch_data = $branches | par-each { |it|
          let counts = if ($it.upstream | is-empty) {
            [0, 0]
          } else {
            let remote_exists = (git show-ref --verify --quiet $"refs/remotes/($it.upstream)"
              | complete
              | $in.exit_code == 0)

            if not $remote_exists {
              [0, 0]
            } else {
              let remote_sha = (git rev-parse $"refs/remotes/($it.upstream)"
                | complete
                | $in.stdout
                | str trim)

              let ahead = (git rev-list --count $"($remote_sha)..($it.branch)"
                | complete
                | $in.stdout
                | into int)
              let behind = (git rev-list --count $"($it.branch)..($remote_sha)"
                | complete
                | $in.stdout
                | into int)

              [$ahead, $behind]
            }
          }

          {
            "Branch": $"(ansi blue)($it.branch)(ansi reset)",
            "Ahead": $"(ansi green)($counts.0)(ansi reset)",
            "Behind": $"(ansi red)($counts.1)(ansi reset)",
            "Last Commit": $"(ansi yellow)($it.time)(ansi reset)",
            "timestamp": $it.timestamp
          }
        }

        # Sort by timestamp (newest first) and remove temporary field
        $branch_data
        | sort-by -r timestamp
        | reject timestamp
        | table --expand
      }
    '';
}
