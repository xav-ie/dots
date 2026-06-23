def spinner [] {
  ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
  | each { |x|
    print -n $"(ansi green)($x)(ansi reset) Fetching remote data...\r"
    sleep 35ms
  }
  return
}
def fmt_cell [width: int] {
    let input = $in | into string
    let trimmed = if ($input | str length) > $width {
        $"($input | str substring 0..($width - 4))..."
    } else {
        $input
    }
    $trimmed | fill -w $width
}
def color [command: string] {
  let input = $in | into string
  $"(ansi $command)($input)(ansi reset)"
}

# List the PRs with `fzf` and check out selected PR.
def main [] {
  let temp_out = (mktemp -t prs-XXXX)
  let fetch_job_id = job spawn {
    try {
      gh pr list --json number,title,headRefName,createdAt,author,isDraft -L 1000
      | save -f $temp_out
    }
  }
  while (job list | where id == $fetch_job_id | length) == 1 {
    spinner
  }

  let $prs = (open $temp_out | from json)
  rm $temp_out
  if (($prs | length) == 0) {
    error make --unspanned { msg: "Error: No pull requests found." }
  }

  let $formattedOut = $prs | each { |pr|
    let createdAt = $pr.createdAt | date humanize
    let numColor = if ($in.isDraft) { "light_gray_dimmed" } else { "green" }
    let output = [
      ($pr.number | fmt_cell 6 | color $numColor)
      ($pr.title | fmt_cell 50)
      ($pr.headRefName | fmt_cell 30 | color cyan)
      ($pr.author.login | fmt_cell 10 | color purple)
      ($createdAt | color default_dimmed)
    ]
    $output | str join " "
  } | str join "\n"
  let header = [
    ("Number" | fmt_cell 6)
    ("Title" | fmt_cell 50)
    ("Branch" | fmt_cell 30)
    ("Author" | fmt_cell 10)
    "Created At"
  ] | str join " "

  let preview_action = 'GH_FORCE_TTY=100% gh pr view {1}'

  # Capture fzf's selection and act on it here in nushell. fzf's `become`
  # would run its body through `$SHELL -c`, which is not guaranteed to be
  # nushell (the tmux/atuin pty stack can export SHELL=bash), so any
  # nu-specific syntax in a `become` string breaks unpredictably.
  let selection = (
    $formattedOut
    | fzf --ansi --header $header --preview $preview_action --preview-window up
    | complete
  )
  if $selection.exit_code != 0 {
    return
  }

  # The number is the first column (ansi-colored, left-filled to width 6).
  let number = ($selection.stdout | ansi strip | str trim | split row ' ' | first)

  if (git status --porcelain | str trim | str length) > 0 {
    GH_FORCE_TTY=100% gh pr view $number
    print "Clean your git directory in order to checkout."
    return
  }

  # `gh pr checkout` is flaky and unreliable, so check out by branch name.
  git fetch origin
  let branch = (gh pr view $number --json headRefName -q .headRefName | str trim)
  git checkout -B $branch $"origin/($branch)"
}
