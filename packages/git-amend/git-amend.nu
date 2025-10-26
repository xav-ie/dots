# Non-interactively amend staged changes to a specific commit.
#
# This is useful when you want to push changes to an old commit without
# manually doing an interactive rebase. It will automatically rebase to
# the target commit, amend it with your staged changes, and continue.
def main [
  commit: string  # The commit SHA to amend (can be short or full SHA)
] {
  # Check if there are staged changes
  let staged_changes = (git diff --cached --quiet | complete)
  if $staged_changes.exit_code == 0 {
    print "Error: No staged changes to amend"
    exit 1
  }

  # Check if the commit exists
  let commit_exists = (git rev-parse --verify $commit | complete)
  if $commit_exists.exit_code != 0 {
    print $"Error: Commit '($commit)' not found"
    exit 1
  }

  # Get the full commit SHA
  let full_commit = (git rev-parse $commit | str trim)

  # Check if this is a merge commit (has multiple parents)
  let is_merge = (git rev-parse --verify $"($commit)^2" | complete)
  if $is_merge.exit_code == 0 {
    print $"Error: Cannot amend merge commit ($full_commit)"
    print "Merge commits combine histories and should not be amended with file changes"
    exit 1
  }

  # Save current HEAD for recovery
  let original_head = (git rev-parse HEAD | str trim)
  print $"Current HEAD: ($original_head)"

  # Get the parent - this won't change after rebase
  let parent_commit = (git rev-parse $"($full_commit)^" | str trim)

  # Create a fixup commit - Git will automatically know to squash this
  # into the target commit during rebase --autosquash
  let fixup = (git commit --fixup $full_commit -S | complete)
  if $fixup.exit_code != 0 {
    print "Error: Failed to create fixup commit"
    print $fixup.stderr
    exit 1
  }

  # Perform autosquash rebase - this will automatically squash the fixup commit
  # into the target commit
  let rebase = (
    GIT_SEQUENCE_EDITOR=true
    git rebase --autosquash -i $"($full_commit)^"
    | complete
  )

  if $rebase.exit_code != 0 {
    print "Error: Failed to rebase"
    print $rebase.stderr
    # Try to abort and reset
    git rebase --abort | complete
    git reset --soft HEAD~1 | complete
    exit 1
  }

  # Find the new SHA - it's the first commit after the parent
  let new_commit = (git log --reverse --format=%H $"($parent_commit)..HEAD" -n 1 | str trim)

  print $"Successfully amended commit ($full_commit) -> ($new_commit)"
}
