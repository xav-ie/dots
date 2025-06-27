{
  gh,
  writeNuApplication,
}:
writeNuApplication {
  name = "base-ref";
  runtimeInputs = [ gh ];
  text = # nu
    ''
      # Find the true divergence point from a base branch.
      #
      # This finds the commit where your current branch actually diverged from
      # the base, excluding commits that were merged into the base branch after
      # your branch was created. Unlike git merge-base, this accounts for cases
      # where the base branch has moved forward since branching, giving you the
      # effective base for diffs and commit ranges.
      def main [base_ref_name?: string] {
        if ($base_ref_name | is-empty) {
          # auto resolves base ref name using gh cli...
          let pr_base = (gh pr view --json baseRefOid -q .baseRefOid
                         | complete
                         | get stdout
                         | str trim)

          if ($pr_base | is-empty) {
            "@{push}"
          } else {
            $pr_base
          }
          # TODO: add more clis
        } else {
          git rev-list --reverse $"(git merge-base HEAD ($base_ref_name))..HEAD"
          | lines
          | each { |commit|
              let parent = (try { git rev-parse $"($commit)^" } | complete)
              if $parent.exit_code == 0 {
                  let parent_hash = ($parent.stdout | str trim)
                  let parent_in_base = (try { git merge-base --is-ancestor $parent_hash ($base_ref_name) } | complete | get exit_code) == 0
                  if $parent_in_base { $commit } else { null }
              } else { null }
          } | where $it != null | last
        }
      }
    '';
}
