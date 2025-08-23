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
      def get-pr-links [] {
        let pr_data = (gh pr view --json baseRefName,headRefName,url | from json)
        let base_ref = $pr_data.baseRefName
        let current_branch = $pr_data.headRefName

        let prev_pr_result = (gh pr view $base_ref --json url,number --jq '{url, number}' | complete)
        let next_prs_result = (gh pr list --base $current_branch --json url,number | complete)

        let prev_pr = if $prev_pr_result.exit_code == 0 {
          $prev_pr_result.stdout | from json
        } else {
          null
        }

        let next_prs = if $next_prs_result.exit_code == 0 and not ($next_prs_result.stdout | str trim | is-empty) {
          $next_prs_result.stdout | from json | each { |pr| $"#($pr.number)" }
        } else {
          []
        }

        let spacing_img = "<img align=\"right\" width=\"1000\" height=\"1\" alt=\"\" src=\"data:,\"  />"

        let pr_data = {
          prev: (if $prev_pr != null { { number: $prev_pr.number, url: $prev_pr.url } } else { null }),
          next: (if ($next_prs | length) > 0 { $next_prs } else { [] })
        }

        let has_prev = ($pr_data.prev != null)
        let has_next = (($pr_data.next | length) > 0)

        if (not $has_prev and not $has_next) {
          ""
        } else {
          # Build table columns based on what PRs exist
          mut columns = []
          mut separators = []

          if $has_prev {
            let prev_link = $"#($pr_data.prev.number)"
            $columns = ($columns | append $"prev pr: ($prev_link) ($spacing_img)")
            $separators = ($separators | append ":-")
          }

          if $has_next {
            let next_links = ($pr_data.next | str join ", ")
            $columns = ($columns | append $"next pr\(s): ($next_links) ($spacing_img)")
            $separators = ($separators | append "-:")
          }

          let table_header = $"| ($columns | str join ' | ') |"
          let table_separator = $"|($separators | str join '|')|"
          let table = [$table_header $table_separator] | str join "\n"

          $"\n\n($table)"
        }
      }

      def get-pr-commits [] {
        git rev-list --reverse $"(base-ref)..HEAD" | lines | each { |hash|
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

      # List the commits in PR, including notes indented, along with links to
      # previous/next PRs
      def main [] {
        let pr_commits = (get-pr-commits)
        let pr_links = (get-pr-links)

        $pr_commits + $pr_links
      }
    '';
}
