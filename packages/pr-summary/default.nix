{
  base-ref,
  git,
  writeNuApplication,
}:
writeNuApplication {
  name = "pr-summary";
  runtimeInputs = [
    base-ref
    git
  ];
  text = # nu
    ''
      # List the commits in PR, including notes indented
      def main [base_ref_input?: string] {
        let base_ref = if ($base_ref_input | is-empty) { base-ref } else { $base_ref_input }
        git rev-list --reverse $"($base_ref)..HEAD" | lines | each { |hash|
          let commit_lines = (git log --pretty=format:"- %B" -n 1 $hash | lines)
          let commit = if ($commit_lines | length) > 1 {
            let first_line = ($commit_lines | first)
            let rest_lines = ($commit_lines | skip 1 | each { |line|
              if ($line | str trim | is-empty) { $line } else { $"  ($line)" }
            })
            ([$first_line] | append $rest_lines | str join "\n")
          } else {
            $commit_lines | str join "\n"
          }

          let result = (git notes show $hash | complete)
          let notes = if $result.exit_code == 0 {
            $result.stdout | lines | each { |line| $"  ($line)" } | str join "\n"
          } else {
            ""
          }

          if ($notes | str trim | is-empty) { $commit } else { $"($commit)\n\n  <!--notes-->\n($notes)" }
        } | str join "\n\n"
      }
    '';
}
