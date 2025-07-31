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
          $next_prs_result.stdout | from json | each { |pr| $"[#($pr.number)]\(($pr.url)\)" }
        } else {
          []
        }

        let prev_link = if $prev_pr != null { $"previous pr: [#($prev_pr.number)]\(($prev_pr.url)\)" } else { "" }
        let next_link = if ($next_prs | length) > 0 { $"next pr\(s\): ($next_prs | str join ', ')" } else { "" }

        let all_links = [$prev_link $next_link] | where $it != "" | str join "\n"

        if ($all_links | is-empty) { "" } else { $"\n\n---\n\n($all_links)" }
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
