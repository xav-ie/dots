def spinner [] {
  ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
  | each { |x|
    print -n $"(ansi green)($x)(ansi reset) Fetching remote data...\r"
    sleep 35ms
  }
  return
}

def main [] {
  let cpus = (sys cpu | length)
  let fetch_job_id = job spawn { git fetch --quiet --all -j $cpus }
  while (job list | where id == $fetch_job_id | length) == 1 {
    spinner
  }

  # Get both local and remote branches
  let local_branches = (git for-each-ref --count=20 --sort=-committerdate
    --format="%(refname:short)|%(upstream:short)|%(committerdate:relative)|%(committerdate:unix)|local" refs/heads/
    | lines
    | par-each { |line| $line | split row "|" }
    | par-each { |cols| {
      branch: ($cols | get 0),
      upstream: ($cols | get 1),
      time: ($cols | get 2),
      timestamp: ($cols | get 3 | into int),
      type: ($cols | get 4)
    }})

  let remote_branches = (git for-each-ref --count=20 --sort=-committerdate
    --format="%(refname:short)||%(committerdate:relative)|%(committerdate:unix)|remote" refs/remotes/
    | lines
    | par-each { |line| $line | split row "|" }
    | par-each { |cols| {
      branch: ($cols | get 0),
      upstream: "",
      time: ($cols | get 2),
      timestamp: ($cols | get 3 | into int),
      type: ($cols | get 4)
    }}
    | where branch !~ "HEAD$")

  let all_branches = ($local_branches ++ $remote_branches)

  let branch_data = $all_branches | par-each { |it|
    if $it.type == "remote" {
      {
        "Branch": $"(ansi cyan)($it.branch)(ansi reset)",
        "Ahead": $"(ansi default_dimmed)-(ansi reset)",
        "Behind": $"(ansi default_dimmed)-(ansi reset)",
        "Last Commit": $"(ansi yellow)($it.time)(ansi reset)",
        "timestamp": $it.timestamp
      }
    } else {
      let counts = if ($it.upstream | is-empty) {
        [0, 0]
      } else {
        let remote_exists = (
          git show-ref --verify --quiet $"refs/remotes/($it.upstream)"
          | complete
          | $in.exit_code == 0
        )
        if not $remote_exists {
          [0, 0]
        } else {
          let remote_sha = (
            git rev-parse $"refs/remotes/($it.upstream)"
            | complete
            | $in.stdout
            | str trim
          )
          let ahead = (
            git rev-list --count $"($remote_sha)..($it.branch)"
            | complete
            | $in.stdout
            | into int
          )
          let behind = (
            git rev-list --count $"($it.branch)..($remote_sha)"
            | complete
            | $in.stdout
            | into int
          )
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
  }

  # Sort by timestamp (newest first) and remove temporary field
  $branch_data
  | sort-by timestamp
  | reject timestamp
  | table -t compact
}
