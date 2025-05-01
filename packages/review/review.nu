def spinner [] {
  ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
  | each { |x|
    print -n $"(ansi green)($x)(ansi reset) Fetching remote data...\r"
    sleep 35ms
  }
  return
}

# Use this command to reset the git repo to the base branch of the PR.
# Useful for reviewing changed files in-editor.
def main [] {
  # 1. Check we are clean and good to reset
  let git_status = (git status --porcelain)
  if ($git_status | str trim | str length) > 0 {
    error make --unspanned { msg: "Error: Git working directory is not clean." }
  }

  # 2. Get the baseRefName
  let temp_out = (mktemp)
  let fetch_job_id = job spawn {
    try {
      git pull;
      gh pr view --json baseRefName
      | from json
      | get baseRefName
      | save -f $temp_out
    }
  }
  while (job list | where id == $fetch_job_id | length) == 1 {
    spinner
  }

  let $baseRefName = (open $temp_out)
  rm $temp_out
  if ($baseRefName == "") {
    error make --unspanned { msg: "Error: No pull request found." }
  }

  # 3. Reset to base branch but keep all changes as uncommitted
  let commit_count = git rev-list --count $"($baseRefName)..HEAD"
  git reset $"HEAD~($commit_count)"

  # 4. Intend to add all files so they show up in (n)vim
  git add -N .
}
